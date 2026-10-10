# Avarim

## for production

run (with production env values):

```bash
sudo docker build --target production --tag Avarim/backend:latest .

sudo docker run -d \
    -e NODE_ENV=production \
    -e HOST=0.0.0.0 \
    -e PORT=3000 \
    -e ALLOWED_ORIGINS=https://domain.tld \
    -e TTS_API_KEY=very_secret \
    -e DB_DATABASE_NAME=Avarim \
    -e DB_SUPPORTS_TRANSACTION=false \
    -e DB_URL=mongodb://mongo:27017 \
    -e MONGODB_USERNAME=user \
    -e MONGODB_PASSWORD=pass \
    -e MEILISEARCH_KEY=very_secret \
    -e MEILISEARCH_HOST=localhost \
    -e MEILISEARCH_PORT=7700 \
    -e STREAM_SIGNING_SECRET=very_secret \
    -e ACCESS_TOKEN_SECRET=very_secret \
    -e REFRESH_TOKEN_SECRET=very_secret \
    -e BUCKET_NAME=name \
    -e S3_STORAGE_ENDPOINT=endpoint \
    -e S3_STORAGE_ACCESS_KEY=very_secret \
    -e S3_STORAGE_SECRET_KEY=very_secret \
    -e S3_API_KEY="very_secret" \
    --network backend_net \
    --network db_net \
    --restart unless-stopped \
    --shm-size=1g \
    --name avarim_backend ghcr.io/hirbod-codes/avarim/backend:1.1.39
```

### To generate secrets

```bash
openssl rand -base64 64
```

## for HTTPS (necessary for development too, because of modern browsers cookie restrictions)

### Make sure you run install command, if you haven't already

run (for Windows)

```bash
.\mkcert.exe -install
.\mkcert.exe localhost 127.0.0.1 ::1
```

### docker run examples

```bash
sudo docker run -d \
    --name mongo \
    --network db_net \
    --restart unless-stopped \
    -p 27017:27017 \
    -e MONGO_INITDB_ROOT_USERNAME=admin \
    -e MONGO_INITDB_ROOT_PASSWORD=strongpassword \
    -v mongo_data:/data/db \
    mongo:8.2.7

sudo docker run -d \
    --name mongo-express \
    --network db_net \
    --restart unless-stopped \
    -p 8081:8081 \
    -e ME_CONFIG_MONGODB_ADMINUSERNAME=admin \
    -e ME_CONFIG_MONGODB_ADMINPASSWORD=strongpassword \
    -e ME_CONFIG_MONGODB_SERVER=mongo \
    mongo-express:latest

sudo docker run -d \
    --name meilisearch \
    --network db_net \
    -p 7700:7700 \
    -e MEILI_MASTER_KEY=supersecret \
    -e MEILI_NO_ANALYTICS=true \
    getmeili/meilisearch:v1
```

## how to commit

feat: add authentication
fix: refresh token rotation
feat!: change API format

Apparently github action doesn't realize new versions when squashing commits when merging.

## In development

run `npm run dev`

### Attention

Ctrl + C DOES NOT work to terminate the app, run `taskkill /IM node.exe /F` on windows.

## To do

1. add routes to update album name and artist name
