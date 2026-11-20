// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ConnectedDevicesFeatureStrings {
    let title: String
    let hubDescription: String
    let noDevices: String
    let unnamedDevice: String
    let menuBarLabel: String
    let oneConnected: String
    let devicesConnectedFormat: String
    let cableDetails: String
    let portFormat: String
    let cableRating: String
    let usbLink: String
    let selectedPower: String

    func formattedCount(_ count: Int) -> String {
        if count == 1 {
            return oneConnected
        }
        return String(format: devicesConnectedFormat, count)
    }
}

extension FeatureStrings {
    static func connectedDevices(_ language: AppLanguage) -> ConnectedDevicesFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhHK: return .zhHK
        case .zhTW: return .zhTW
        }
    }
}

private extension ConnectedDevicesFeatureStrings {
    static let enUS = ConnectedDevicesFeatureStrings(
        title: "Connected Devices",
        hubDescription: "Count connected external USB peripherals",
        noDevices: "No external devices connected",
        unnamedDevice: "USB Device",
        menuBarLabel: "USB",
        oneConnected: "1 device connected",
        devicesConnectedFormat: "%d devices connected",
        cableDetails: "USB-C cable details",
        portFormat: "USB-C port %d",
        cableRating: "Cable rating",
        usbLink: "USB link",
        selectedPower: "Selected power"
    )

    static let ptBR = ConnectedDevicesFeatureStrings(
        title: "Dispositivos conectados",
        hubDescription: "Contar periféricos USB externos conectados",
        noDevices: "Nenhum dispositivo externo conectado",
        unnamedDevice: "Dispositivo USB",
        menuBarLabel: "USB",
        oneConnected: "1 dispositivo conectado",
        devicesConnectedFormat: "%d dispositivos conectados",
        cableDetails: "Detalhes dos cabos USB-C",
        portFormat: "Porta USB-C %d",
        cableRating: "Capacidade do cabo",
        usbLink: "Conexão USB",
        selectedPower: "Potência selecionada"
    )

    static let tr = ConnectedDevicesFeatureStrings(
        title: "Bağlı Aygıtlar",
        hubDescription: "Bağlı harici USB çevre birimlerini say",
        noDevices: "Bağlı harici aygıt yok",
        unnamedDevice: "USB Aygıtı",
        menuBarLabel: "USB",
        oneConnected: "1 aygıt bağlı",
        devicesConnectedFormat: "%d aygıt bağlı",
        cableDetails: "USB-C kablo ayrıntıları",
        portFormat: "USB-C bağlantı noktası %d",
        cableRating: "Kablo kapasitesi",
        usbLink: "USB bağlantısı",
        selectedPower: "Seçilen güç"
    )

    static let ru = ConnectedDevicesFeatureStrings(
        title: "Подключенные устройства",
        hubDescription: "Подсчет подключенных внешних USB-устройств",
        noDevices: "Нет подключенных внешних устройств",
        unnamedDevice: "USB-устройство",
        menuBarLabel: "USB",
        oneConnected: "Подключено 1 устройство",
        devicesConnectedFormat: "Подключено устройств: %d",
        cableDetails: "Сведения о кабелях USB-C",
        portFormat: "Порт USB-C %d",
        cableRating: "Характеристики кабеля",
        usbLink: "Соединение USB",
        selectedPower: "Выбранная мощность"
    )

    static let es = ConnectedDevicesFeatureStrings(
        title: "Dispositivos conectados",
        hubDescription: "Contar periféricos USB externos conectados",
        noDevices: "No hay dispositivos externos conectados",
        unnamedDevice: "Dispositivo USB",
        menuBarLabel: "USB",
        oneConnected: "1 dispositivo conectado",
        devicesConnectedFormat: "%d dispositivos conectados",
        cableDetails: "Detalles de cables USB-C",
        portFormat: "Puerto USB-C %d",
        cableRating: "Capacidad del cable",
        usbLink: "Conexión USB",
        selectedPower: "Potencia seleccionada"
    )
    static let sk = ConnectedDevicesFeatureStrings(
        title: "Pripojené zariadenia",
        hubDescription: "Počíta pripojené externé zariadenia USB",
        noDevices: "Nie sú pripojené žiadne externé zariadenia",
        unnamedDevice: "Zariadenie USB",
        menuBarLabel: "USB",
        oneConnected: "1 pripojené zariadenie",
        devicesConnectedFormat: "Pripojené zariadenia: %d",
        cableDetails: "Podrobnosti o kábloch USB-C",
        portFormat: "Port USB-C %d",
        cableRating: "Kapacita kábla",
        usbLink: "Pripojenie USB",
        selectedPower: "Zvolený výkon"
    )

    static let de = ConnectedDevicesFeatureStrings(
        title: "Verbundene Geräte",
        hubDescription: "Angeschlossene externe USB-Geräte zählen",
        noDevices: "Keine externen Geräte verbunden",
        unnamedDevice: "USB-Gerät",
        menuBarLabel: "USB",
        oneConnected: "1 Gerät verbunden",
        devicesConnectedFormat: "%d Geräte verbunden",
        cableDetails: "USB-C-Kabeldetails",
        portFormat: "USB-C-Anschluss %d",
        cableRating: "Kabelspezifikation",
        usbLink: "USB-Verbindung",
        selectedPower: "Gewählte Leistung"
    )

    static let fr = ConnectedDevicesFeatureStrings(
        title: "Appareils connectés",
        hubDescription: "Compter les périphériques USB externes connectés",
        noDevices: "Aucun appareil externe connecté",
        unnamedDevice: "Appareil USB",
        menuBarLabel: "USB",
        oneConnected: "1 appareil connecté",
        devicesConnectedFormat: "%d appareils connectés",
        cableDetails: "Détails des câbles USB-C",
        portFormat: "Port USB-C %d",
        cableRating: "Capacité du câble",
        usbLink: "Liaison USB",
        selectedPower: "Puissance sélectionnée"
    )

    static let it = ConnectedDevicesFeatureStrings(
        title: "Dispositivi collegati",
        hubDescription: "Conta le periferiche USB esterne collegate",
        noDevices: "Nessun dispositivo esterno collegato",
        unnamedDevice: "Dispositivo USB",
        menuBarLabel: "USB",
        oneConnected: "1 dispositivo collegato",
        devicesConnectedFormat: "%d dispositivi collegati",
        cableDetails: "Dettagli dei cavi USB-C",
        portFormat: "Porta USB-C %d",
        cableRating: "Capacità del cavo",
        usbLink: "Collegamento USB",
        selectedPower: "Potenza selezionata"
    )

    static let ja = ConnectedDevicesFeatureStrings(
        title: "接続されたデバイス",
        hubDescription: "接続されている外部USB周辺機器をカウント",
        noDevices: "接続されている外部デバイスはありません",
        unnamedDevice: "USBデバイス",
        menuBarLabel: "USB",
        oneConnected: "1台のデバイスが接続中",
        devicesConnectedFormat: "%d台のデバイスが接続中",
        cableDetails: "USB-Cケーブルの詳細",
        portFormat: "USB-Cポート %d",
        cableRating: "ケーブル定格",
        usbLink: "USBリンク",
        selectedPower: "選択した電力"
    )

    static let ko = ConnectedDevicesFeatureStrings(
        title: "연결된 기기",
        hubDescription: "연결된 외부 USB 주변기기 수 측정",
        noDevices: "연결된 외부 기기 없음",
        unnamedDevice: "USB 기기",
        menuBarLabel: "USB",
        oneConnected: "기기 1개 연결됨",
        devicesConnectedFormat: "기기 %d개 연결됨",
        cableDetails: "USB-C 케이블 세부 정보",
        portFormat: "USB-C 포트 %d",
        cableRating: "케이블 정격",
        usbLink: "USB 링크",
        selectedPower: "선택된 전력"
    )
    static let uk = ConnectedDevicesFeatureStrings(
        title: "Підключені пристрої",
        hubDescription: "Підраховує підключені зовнішні USB-пристрої",
        noDevices: "Немає підключених зовнішніх пристроїв",
        unnamedDevice: "USB-пристрій",
        menuBarLabel: "USB",
        oneConnected: "Підключено 1 пристрій",
        devicesConnectedFormat: "Підключено пристроїв: %d",
        cableDetails: "Відомості про кабелі USB-C",
        portFormat: "Порт USB-C %d",
        cableRating: "Характеристики кабелю",
        usbLink: "З’єднання USB",
        selectedPower: "Вибрана потужність"
    )

    static let zhHans = ConnectedDevicesFeatureStrings(
        title: "已连接设备",
        hubDescription: "统计连接的外接 USB 设备数量",
        noDevices: "未连接外接设备",
        unnamedDevice: "USB 设备",
        menuBarLabel: "USB",
        oneConnected: "已连接 1 台设备",
        devicesConnectedFormat: "已连接 %d 台设备",
        cableDetails: "USB-C 线缆详情",
        portFormat: "USB-C 端口 %d",
        cableRating: "线缆额定规格",
        usbLink: "USB 链路",
        selectedPower: "所选功率"
    )

    static let zhHK = ConnectedDevicesFeatureStrings(
        title: "已連接裝置",
        hubDescription: "統計連接的外接 USB 裝置數量",
        noDevices: "未連接外接裝置",
        unnamedDevice: "USB 裝置",
        menuBarLabel: "USB",
        oneConnected: "已連接 1 部裝置",
        devicesConnectedFormat: "已連接 %d 部裝置",
        cableDetails: "USB-C 連接線詳情",
        portFormat: "USB-C 連接埠 %d",
        cableRating: "連接線額定規格",
        usbLink: "USB 連線",
        selectedPower: "所選功率"
    )

    static let zhTW = ConnectedDevicesFeatureStrings(
        title: "已連接裝置",
        hubDescription: "統計連接的外接 USB 裝置數量",
        noDevices: "未連接外接裝置",
        unnamedDevice: "USB 裝置",
        menuBarLabel: "USB",
        oneConnected: "已連接 1 部裝置",
        devicesConnectedFormat: "已連接 %d 部裝置",
        cableDetails: "USB-C 連接線詳細資訊",
        portFormat: "USB-C 連接埠 %d",
        cableRating: "連接線額定規格",
        usbLink: "USB 連線",
        selectedPower: "所選功率"
    )
}
