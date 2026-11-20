// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

use anyhow::{Context, Result, anyhow, ensure};
use localsend::crypto::cert::{SelfSignedCert, generate_self_signed};
use localsend::discovery::{
    DEFAULT_DISCOVERY_TIMEOUT, DeviceChannel, DeviceIdentity, DiscoveredDevice, DiscoveryConfig,
};
use localsend::http::client::v2::LsHttpClientV2;
use localsend::http::dto_v2::{PrepareUploadRequestDtoV2, RegisterDtoV2};
use localsend::http::server::common::save::FileUploadTarget;
use localsend::http::server::v2::{PrepareUploadDecisionV2, ServerEventV2};
use localsend::http::server::web::WebConfig;
use localsend::http::server::{ServerConfigV2, TlsConfig, start_with_port};
use localsend::http::state::ClientInfo;
use localsend::model::discovery::{DeviceType, PROTOCOL_VERSION_V2, ProtocolType};
use localsend::model::transfer::FileDto;
use localsend::multicast::{DEFAULT_MULTICAST_GROUP, DEFAULT_PORT, MulticastDevice};
use localsend::reqwest::Body;
use localsend::util::interface::InterfaceFilter;
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet},
    path::{Path, PathBuf},
    time::Duration,
};
use tokio::{
    fs,
    io::{AsyncBufReadExt, BufReader},
    sync::{mpsc, oneshot},
};
use tokio_util::{io::ReaderStream, sync::CancellationToken};

const ALIAS: &str = "Vorssaint on Mac";
const MAX_FILES: usize = 64;
const MAX_RECEIVE_BYTES: u64 = 16 * 1024 * 1024 * 1024;

fn emit(event: Value) {
    println!("{}", event);
}

fn file_name_allowed(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 255
        && name != "."
        && name != ".."
        && !name
            .chars()
            .any(|c| matches!(c, '/' | '\\' | ':') || c.is_control())
}

fn register(cert: &SelfSignedCert, port: u16) -> RegisterDtoV2 {
    RegisterDtoV2 {
        alias: ALIAS.into(),
        version: PROTOCOL_VERSION_V2.into(),
        device_model: Some("macOS".into()),
        device_type: Some(DeviceType::Desktop),
        fingerprint: cert.fingerprint.clone(),
        port,
        protocol: ProtocolType::Https,
        download: false,
    }
}

#[tokio::main]
async fn main() {
    if run().await.is_err() {
        emit(json!({"kind":"error"}));
        std::process::exit(1);
    }
}

async fn run() -> Result<()> {
    let directory = std::env::args_os().nth(1).map(PathBuf::from);
    let stage = directory
        .as_ref()
        .map(|root| {
            tempfile::Builder::new()
                .prefix(".vorssaint-")
                .tempdir_in(root)
                .map(std::sync::Arc::new)
        })
        .transpose()?;
    let mut receives = tokio::task::JoinSet::new();
    let cert = generate_self_signed()?;
    let (events, mut server_events) = mpsc::channel(32);
    let (server_stop, stop_receiver) = oneshot::channel();
    let info = register(&cert, DEFAULT_PORT);
    let server = start_with_port(
        DEFAULT_PORT,
        Some(TlsConfig {
            cert: cert.certificate_pem.clone(),
            private_key: cert.private_key_pem.clone(),
        }),
        ClientInfo {
            alias: info.alias.clone(),
            version: info.version.clone(),
            device_model: info.device_model.clone(),
            device_type: info.device_type.clone(),
            token: info.fingerprint.clone(),
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            verify_checksums: true,
            event_tx: events,
        }),
        WebConfig::default(),
        stop_receiver,
    )
    .await?;
    let (discovery_stop, discovery_stop_rx) = oneshot::channel();
    let discovery = localsend::discovery::start(
        DiscoveryConfig {
            group: DEFAULT_MULTICAST_GROUP,
            group_v6: None,
            port: DEFAULT_PORT,
            interface_filter: InterfaceFilter::default(),
            timeout: DEFAULT_DISCOVERY_TIMEOUT,
            event_tx: None,
            device: MulticastDevice {
                alias: info.alias.clone(),
                version: info.version.clone(),
                device_model: info.device_model.clone(),
                device_type: info.device_type,
                fingerprint: info.fingerprint.clone(),
                port: server.port(),
                protocol: ProtocolType::Https,
                download: false,
            },
            identity: DeviceIdentity {
                cert_pem: cert.certificate_pem.clone(),
                private_key_pem: cert.private_key_pem.clone(),
            },
        },
        discovery_stop_rx,
    )
    .await;
    discovery.announce().await;
    emit(json!({"kind":"ready"}));
    let mut stdin = BufReader::new(tokio::io::stdin()).lines();
    let mut scan = tokio::time::interval(Duration::from_secs(2));
    let mut pending: Option<Incoming> = None;
    let mut sending = None;
    let cancellation = CancellationToken::new();
    loop {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => break,
            command = stdin.next_line() => {
                let Some(command) = command? else { break };
                let Ok(command) = serde_json::from_str::<Value>(&command) else { continue };
                match command["kind"].as_str() {
                    Some("refresh") => discovery.announce().await,
                    Some("accept") | Some("decline") => {
                        if let Some(offer) = pending.as_mut()
                            .filter(|offer| command["id"].as_str() == Some(&offer.id)) {
                            if let Some(decision) = offer.decision.take() {
                                offer.accepted = command["kind"] == "accept";
                                let choice = if offer.accepted {
                                    PrepareUploadDecisionV2::Accept(offer.files.keys().cloned().collect())
                                } else { PrepareUploadDecisionV2::Decline };
                                let _ = decision.send(choice);
                                if !offer.accepted { pending = None; }
                            }
                        }
                    }
                    Some("send") if sending.is_none() => {
                        let id = command["id"].as_str().unwrap_or_default();
                        let files: Vec<PathBuf> = serde_json::from_value::<Vec<String>>(command["paths"].clone())
                            .unwrap_or_default().into_iter().map(PathBuf::from).collect();
                        let peer = discovery.device_by_fingerprint(id)
                            .filter(|p| p.confirmed)
                            .and_then(|p| p.get_ranked_channels().into_iter()
                                .find(|c| c.http().is_some_and(|h| h.protocol == ProtocolType::Https))
                                .cloned().map(|c| (c, p.device.fingerprint)));
                        if let Some((channel, fingerprint)) = peer {
                            let client = LsHttpClientV2::try_new(&cert.private_key_pem, &cert.certificate_pem,
                                Some(fingerprint), Some(Duration::from_secs(300)))?;
                            let sender = register(&cert, server.port());
                            let token = cancellation.child_token();
                            let task_token = token.clone();
                            let handle = tokio::spawn(async move {
                                if send(&client, channel, sender, files, task_token).await.is_err() {
                                    emit(json!({"kind":"sendFailed"}));
                                } else { emit(json!({"kind":"sendComplete"})); }
                            });
                            sending = Some((handle, token));
                        } else { emit(json!({"kind":"sendFailed"})); }
                    }
                    Some("cancelSend") => {
                        if let Some((_, token)) = sending.as_ref() { token.cancel(); }
                    }
                    _ => {}
                }
            }
            _ = scan.tick() => {
                if sending.as_ref().is_some_and(|(task, _)| task.is_finished()) { sending = None; }
                let devices: Vec<_> = discovery.devices().into_iter()
                    .filter(|peer| peer.confirmed && peer.get_ranked_channels().iter().any(|channel|
                        channel.http().is_some_and(|http| http.protocol == ProtocolType::Https)))
                    .take(100).map(|peer| json!({"id":peer.device.fingerprint, "name":peer.device.alias})).collect();
                emit(json!({"kind":"peers", "peers":devices}));
            }
            _ = receives.join_next(), if !receives.is_empty() => {},
            Some(event) = server_events.recv() => match event {
                ServerEventV2::Register { ip, info } if info.protocol == ProtocolType::Https => {
                    let channel = DeviceChannel::Http(localsend::discovery::HttpChannel {
                        host: ip.to_string(), port: info.port, protocol: info.protocol
                    });
                    discovery.observe_inbound(DiscoveredDevice {
                        alias: info.alias, version: info.version, device_model: info.device_model,
                        device_type: info.device_type, fingerprint: info.fingerprint, channel, download: false,
                    }).await;
                }
                ServerEventV2::PrepareUpload { session_id, info, files, decision_tx, cert_fingerprint, .. } => {
                    let valid = directory.is_some() && pending.is_none() && cert_fingerprint.is_some()
                        && !files.is_empty() && files.len() <= MAX_FILES
                        && files.values().all(|f| file_name_allowed(&f.file_name) && !f.file_type.starts_with("text/plain;"))
                        && files.values().try_fold(0_u64, |sum, f| sum.checked_add(f.size))
                            .is_some_and(|sum| sum <= MAX_RECEIVE_BYTES);
                    if valid {
                        let names: Vec<_> = files.values().map(|file| &file.file_name).collect();
                        emit(json!({"kind":"offer", "id":session_id, "name":info.alias, "files":names}));
                        pending = Some(Incoming { id:session_id, files, decision:Some(decision_tx), accepted:false });
                    } else { let _ = decision_tx.send(PrepareUploadDecisionV2::Decline); }
                }
                ServerEventV2::FileUpload { session_id, file_id, target_tx, .. } => {
                    if let Some(file) = pending.as_ref().filter(|offer| offer.accepted && offer.id == session_id)
                        .and_then(|offer| offer.files.get(&file_id))
                        && let (Some(directory), Some(stage)) = (directory.as_ref(), stage.clone())
                    {
                        // Private staging on the same volume permits non-overwriting publication.
                        let Ok(temp) = tempfile::NamedTempFile::new_in(stage.path()) else { continue };
                        let file_size = file.size;
                        let destination = directory.join(&file.file_name);
                        let (result_tx, result_rx) = oneshot::channel();
                        if target_tx.send(FileUploadTarget::Path { path:temp.path().to_path_buf(), result_tx, progress_tx:None }).is_ok() {
                            receives.spawn(async move {
                                let _stage = stage;
                                let good = matches!(result_rx.await, Ok(Ok(())))
                                    && fs::metadata(temp.path()).await.is_ok_and(|meta| meta.len() == file_size)
                                    && fs::hard_link(temp.path(), &destination).await.is_ok();
                                emit(json!({"kind":if good {"receiveComplete"} else {"receiveFailed"}}));
                            });
                        }
                    }
                }
                ServerEventV2::SessionEnd { session_id, .. }
                | ServerEventV2::PrepareUploadAborted { session_id, .. } => {
                    if pending.as_ref().is_some_and(|offer| offer.id == session_id) {
                        pending = None;
                        emit(json!({"kind":"offerEnded", "id":session_id}));
                    }
                }
                ServerEventV2::ListenerFailed { .. } => break,
                _ => {}
            }
        }
    }
    cancellation.cancel();
    let _ = server_stop.send(());
    let _ = discovery_stop.send(());
    let _ = tokio::time::timeout(Duration::from_secs(3), server.wait_stopped()).await;
    receives.shutdown().await;
    Ok(())
}

struct Incoming {
    id: String,
    files: HashMap<String, FileDto>,
    decision: Option<oneshot::Sender<PrepareUploadDecisionV2>>,
    accepted: bool,
}

async fn send(
    client: &LsHttpClientV2,
    channel: DeviceChannel,
    info: RegisterDtoV2,
    paths: Vec<PathBuf>,
    cancel: CancellationToken,
) -> Result<()> {
    ensure!(
        !paths.is_empty() && paths.len() <= MAX_FILES,
        "invalid file count"
    );
    let channel = channel.http().context("no HTTPS channel")?;
    let mut sources = HashMap::new();
    let mut files = HashMap::new();
    for (index, path) in paths.into_iter().enumerate() {
        let name = Path::new(&path)
            .file_name()
            .and_then(|name| name.to_str())
            .context("invalid name")?
            .to_owned();
        ensure!(file_name_allowed(&name), "invalid file name");
        let file = fs::File::open(&path).await?;
        let metadata = file.metadata().await?;
        ensure!(metadata.is_file(), "only files are supported");
        let id = index.to_string();
        files.insert(
            id.clone(),
            FileDto {
                id: id.clone(),
                file_name: name,
                size: metadata.len(),
                file_type: "application/octet-stream".into(),
                sha256: None,
                preview: None,
                metadata: None,
            },
        );
        sources.insert(id, file);
    }
    let offer = client
        .prepare_upload(
            ProtocolType::Https,
            &channel.host,
            channel.port,
            None,
            PrepareUploadRequestDtoV2 { info, files },
            None,
            cancel.clone(),
        )
        .await?;
    let accepted = offer.response.ok_or_else(|| anyhow!("no accepted files"))?;
    let mut completed = 0;
    let total = sources.len();
    let mut uploaded = HashSet::new();
    for (id, token) in accepted.files {
        let Some(file) = sources.remove(&id) else {
            continue;
        };
        let result = client
            .upload(
                ProtocolType::Https,
                &channel.host,
                channel.port,
                None,
                &accepted.session_id,
                &id,
                &token,
                Body::wrap_stream(ReaderStream::new(file)),
                cancel.clone(),
            )
            .await;
        if let Err(error) = result {
            let _ = tokio::time::timeout(
                Duration::from_secs(3),
                client.cancel(
                    ProtocolType::Https,
                    &channel.host,
                    channel.port,
                    &accepted.session_id,
                ),
            )
            .await;
            return Err(error.into());
        }
        uploaded.insert(id);
        completed += 1;
        emit(json!({"kind":"progress", "completed":completed, "total":total}));
    }
    ensure!(uploaded.len() == total, "some files were declined");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_receive_names() {
        assert!(file_name_allowed("foto 01.jpg"));
        assert!(!file_name_allowed("../photo.jpg"));
        assert!(!file_name_allowed("a\\b"));
        assert!(!file_name_allowed("."));
        assert!(!file_name_allowed("a\nb"));
    }
    #[tokio::test]
    async fn uploads_file_to_confirming_https_peer() -> Result<()> {
        let peer = generate_self_signed()?;
        let sender = generate_self_signed()?;
        let (events, mut receiver) = mpsc::channel(8);
        let (stop, stop_rx) = oneshot::channel();
        let folder = tempfile::tempdir()?;
        let source = folder.path().join("sample.txt");
        let destination = folder.path().join("received");
        fs::write(&source, b"Vorssaint LocalSend verification").await?;

        let server = start_with_port(
            0,
            Some(TlsConfig {
                cert: peer.certificate_pem.clone(),
                private_key: peer.private_key_pem.clone(),
            }),
            ClientInfo {
                alias: "Local test peer".into(),
                version: PROTOCOL_VERSION_V2.into(),
                device_model: None,
                device_type: None,
                token: peer.fingerprint.clone(),
            },
            None,
            Some(ServerConfigV2 {
                pin: None,
                verify_checksums: true,
                event_tx: events,
            }),
            WebConfig::default(),
            stop_rx,
        )
        .await?;

        let destination_for_server = destination.clone();
        let receive = tokio::spawn(async move {
            while let Some(event) = receiver.recv().await {
                match event {
                    ServerEventV2::PrepareUpload {
                        files,
                        cert_fingerprint,
                        decision_tx,
                        ..
                    } => {
                        assert!(cert_fingerprint.is_some());
                        assert_eq!(files.len(), 1);
                        let _ = decision_tx
                            .send(PrepareUploadDecisionV2::Accept(files.into_keys().collect()));
                    }
                    ServerEventV2::FileUpload { target_tx, .. } => {
                        let (result_tx, result_rx) = oneshot::channel();
                        target_tx
                            .send(FileUploadTarget::Path {
                                path: destination_for_server.clone(),
                                result_tx,
                                progress_tx: None,
                            })
                            .unwrap();
                        return result_rx.await.unwrap();
                    }
                    _ => {}
                }
            }
            Err("no transfer".into())
        });

        let client = LsHttpClientV2::try_new(
            &sender.private_key_pem,
            &sender.certificate_pem,
            Some(peer.fingerprint),
            Some(Duration::from_secs(10)),
        )?;
        send(
            &client,
            DeviceChannel::Http(localsend::discovery::HttpChannel {
                host: "127.0.0.1".into(),
                port: server.port(),
                protocol: ProtocolType::Https,
            }),
            register(&sender, server.port()),
            vec![source.clone()],
            CancellationToken::new(),
        )
        .await?;
        assert!(receive.await?.is_ok());
        assert_eq!(fs::read(source).await?, fs::read(destination).await?);
        let _ = stop.send(());
        Ok(())
    }
}
