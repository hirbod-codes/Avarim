# In production

1. Copy swarm folder in your vps
2. run

```shell
cd <path>/swarm

sudo docker swarm init

sudo apt update && sudo apt install -y jq

sudo chmod +x ./rotate_secrets.sh ./deploy.sh

AVARIM_TTS_API_KEY=api_key \
AVARIM_MONGODB_USERNAME=admin \
AVARIM_MONGODB_PASSWORD=password \
AVARIM_BUCKET_NAME=name \
AVARIM_S3_STORAGE_ENDPOINT=endpoint \
AVARIM_S3_STORAGE_ACCESS_KEY=access_key \
AVARIM_S3_STORAGE_SECRET_KEY=secret_key \
AVARIM_S3_API_KEY=api_key \
./rotate_secrets.sh ./secrets.env

# Because swarm doesn't automatically load .env file, we use compose config instead.
./deploy.sh memoize
```

## To add a new secret

1. Add them in SECRET_ORDER, MODE and TARGET_SERVICE collections in `rotate_secrets.sh` file
2. Add them in top level secrets object and secrets object of each service

## Note before running ./deploy.sh

In case compose and env and configuration files have transferred with windows line endings, run:

```bash
sed -i 's/\r$//' ./*.*
sed -i 's/\r$//' ./grafana/dashboards/*.*
sed -i 's/\r$//' ./grafana/provisioning/dashboards/*.*
sed -i 's/\r$//' ./grafana/provisioning/datasources/*.*
sed -i 's/\r$//' ./.env
```
