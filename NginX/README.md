# Run

```bash
# At root directory
docker build --target production --tag nginx:latest -f Nginx/Dockerfile .

docker run -d \
    --name nginx \
    -p 80:80 \
    -p 443:443 \
    --network backend_net \
    --restart unless-stopped \
    nginx
```
