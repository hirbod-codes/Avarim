# To use

1. Copy swarm folder in your vps
2. run

```shell
mkdir -p ./grafana/grafana_data ./tempo_data ./prometheus_data ./loki_data ./alloy_data ./mongo_data ./meili_data ./redis_data

sudo chown -R 472:472 ./grafana/grafana_data
sudo chown -R 10001:10001 ./tempo_data ./loki_data
sudo chown -R 65534:65534 ./prometheus_data

sudo docker compose -f compose.yml up -d --remove-orphans
```

## Note before running ./deploy.sh

In case compose and env and configuration files have transferred with windows line endings, run:

```bash
sed -i 's/\r$//' ./*.*
sed -i 's/\r$//' ./.env
sed -i 's/\r$//' ./grafana/dashboards/*.*
sed -i 's/\r$//' ./grafana/provisioning/dashboards/*.*
sed -i 's/\r$//' ./grafana/provisioning/datasources/*.*
```
