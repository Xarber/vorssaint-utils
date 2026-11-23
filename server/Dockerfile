FROM node:24-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5
WORKDIR /srv/relay
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund
COPY sync.mjs backup.mjs ./
USER node
ENV BIND_ADDRESS=0.0.0.0
EXPOSE 8789
CMD ["node", "sync.mjs"]
