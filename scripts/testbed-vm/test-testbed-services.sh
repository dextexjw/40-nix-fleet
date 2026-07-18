#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="testbed-vm"
HOST_IP="10.2.20.129"
SKIP_SURE_SMOKE="${SKIP_SURE_SMOKE:-0}"
SKIP_OUTLINE_SMOKE="${SKIP_OUTLINE_SMOKE:-0}"
SKIP_KARAKEEP_SMOKE="${SKIP_KARAKEEP_SMOKE:-0}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v colmena >/dev/null 2>&1 || die "colmena is missing; run nix develop first"

cd "$ROOT"

printf 'Checking key testbed services...\n'
services=(postgresql mysql redis-affine redis-keeper redis-plane listmonk homebox mailpit-testbed gitea phpfpm-firefly-iii phpfpm-invoiceplane podman-affine podman-fizzy podman-kaneo podman-keeper podman-metube podman-plane-rabbitmq podman-plane-api podman-plane-worker podman-plane-beat-worker podman-plane-live podman-plane-web podman-plane-admin podman-plane-space podman-postiz podman-postiz-postgres podman-postiz-redis podman-postiz-temporal podman-postiz-temporal-elasticsearch podman-postiz-temporal-postgres stirling-pdf nginx)
if [ "$SKIP_KARAKEEP_SMOKE" != 1 ] && colmena exec --on "$HOST" -- "test \"\$(systemctl show -P LoadState podman-karakeep.service 2>/dev/null || true)\" = loaded"; then
  services+=(podman-karakeep podman-karakeep-browser podman-karakeep-meilisearch)
else
  SKIP_KARAKEEP_SMOKE=1
fi
if [ "$SKIP_OUTLINE_SMOKE" != 1 ]; then
  services+=(redis-outline podman-outline)
fi
if [ "$SKIP_SURE_SMOKE" != 1 ]; then
  services+=(redis-sure podman-sure-web podman-sure-worker)
fi
for service in "${services[@]}"; do
  colmena exec --on "$HOST" -- systemctl is-active --quiet "$service.service"
done
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P LoadState podman-plane-minio.service 2>/dev/null || true)\" = not-found"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result kaneo-postgresql-password.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result keeper-postgresql-password.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result listmonk-oidc-config.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result affine-postgresql-extensions.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result affine-postgresql-password.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result gitea-oidc-config.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result invoiceplane-mysql-password.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result invoiceplane-prepare.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result invoiceplane-bootstrap.service)\" = success"
if [ "$SKIP_OUTLINE_SMOKE" != 1 ]; then
  colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result outline-postgresql-password.service)\" = success"
fi
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result plane-postgresql-password.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result plane-rabbitmq-config.service)\" = success"
if [ "$SKIP_SURE_SMOKE" != 1 ]; then
  colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result sure-postgresql-password.service)\" = success"
fi
colmena exec --on "$HOST" -- systemctl is-active --quiet firefly-iii-cron.timer
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result plane-migrate.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result plane-admin-bootstrap.service)\" = success"

printf 'Checking testbed appdata and local listeners...\n'
colmena exec --on "$HOST" -- test -d /srv/appsdata/affine/storage
if [ "$SKIP_KARAKEEP_SMOKE" != 1 ]; then
  colmena exec --on "$HOST" -- test -d /srv/appsdata/karakeep/data
  colmena exec --on "$HOST" -- test -d /srv/appsdata/karakeep/meilisearch
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:9090/ >/dev/null"
fi
colmena exec --on "$HOST" -- test -d /srv/appsdata/affine/config
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:3010/ >/dev/null"
colmena exec --on "$HOST" -- "sudo -u postgres psql -d affine -tAc 'select 1' | tr -d '[:space:]' | grep -Fxq 1"
colmena exec --on "$HOST" -- test -d /srv/appsdata/firefly-iii
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: firefly.jax22.com' http://${HOST_IP}/ >/dev/null"
colmena exec --on "$HOST" -- test -d /srv/appsdata/gitea
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9070/ >/dev/null"
colmena exec --on "$HOST" -- "sudo -u postgres psql -d gitea -tAc 'select 1' | tr -d '[:space:]' | grep -Fxq 1"
colmena exec --on "$HOST" -- "sudo -u postgres psql -d gitea -tAc \"select count(*) > 0 from login_source where name = 'authentik';\" | tr -d '[:space:]' | grep -Fxq t"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9070/user/login | grep -Fiq 'authentik'"
colmena exec --on "$HOST" -- test -d /srv/appsdata/stirling-pdf
colmena exec --on "$HOST" -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 http://${HOST_IP}:8086/); case \"\$status\" in 2*|30[1278]|401|403) exit 0 ;; *) echo \"unexpected Stirling PDF status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on "$HOST" -- test -d /srv/appsdata/fizzy/storage
colmena exec --on "$HOST" -- "test \"\$(stat -c '%u:%g' /srv/appsdata/fizzy/storage)\" = 1000:1000"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9010/up >/dev/null"
colmena exec --on "$HOST" -- test -d /srv/appsdata/keeper/redis
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:3000/ >/dev/null"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:3001/api/health >/dev/null"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:3001/api/auth/capabilities | grep -Eq '\"google\":(true|false)'"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:3001/api/auth/capabilities | grep -Eq '\"microsoft\":(true|false)'"
colmena exec --on "$HOST" -- sudo test -d /srv/appsdata/homebox/data
colmena exec --on "$HOST" -- "test \"\$(sudo stat -c '%U:%G' /srv/appsdata/homebox/data)\" = homebox:homebox"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:7745/api/v1/status | grep -Fq '\"health\":true'"
colmena exec --on "$HOST" -- test -d /srv/appsdata/invoiceplane/www
colmena exec --on "$HOST" -- "test \"\$(sudo stat -c '%U:%G' /srv/appsdata/invoiceplane/www/ipconfig.php)\" = invoiceplane:nginx"
colmena exec --on "$HOST" -- "sudo grep -Fxq 'IP_URL=https://invoiceplane.jax22.com/' /srv/appsdata/invoiceplane/www/ipconfig.php"
colmena exec --on "$HOST" -- "sudo grep -Fxq 'REMOVE_INDEXPHP=true' /srv/appsdata/invoiceplane/www/ipconfig.php"
colmena exec --on "$HOST" -- "sudo grep -Fxq 'SETUP_COMPLETED=true' /srv/appsdata/invoiceplane/www/ipconfig.php"
colmena exec --on "$HOST" -- "sudo grep -Fxq 'DISABLE_SETUP=true' /srv/appsdata/invoiceplane/www/ipconfig.php"
colmena exec --on "$HOST" -- "mysql --batch --skip-column-names --protocol=socket information_schema -e \"SELECT COUNT(*) FROM tables WHERE table_schema='invoiceplane' AND table_name='ip_versions';\" | tr -d '[:space:]' | grep -Fxq 1"
colmena exec --on "$HOST" -- "mysql --batch --skip-column-names --protocol=socket invoiceplane -e 'SELECT COUNT(*) > 0 FROM ip_versions;' | tr -d '[:space:]' | grep -Fxq 1"
colmena exec --on "$HOST" -- "mysql --batch --skip-column-names --protocol=socket invoiceplane -e 'SELECT COUNT(*) > 0 FROM ip_users;' | tr -d '[:space:]' | grep -Fxq 1"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: invoiceplane.jax22.com' http://${HOST_IP}:9060/sessions/login | grep -Eiq 'invoiceplane|login|password'"
colmena exec --on "$HOST" -- "sh -lc 'headers=\$(mktemp); trap \"rm -f \\\"\$headers\\\"\" EXIT; curl -fsS -D \"\$headers\" -o /dev/null --max-time 10 -H \"Host: invoiceplane.jax22.com\" http://${HOST_IP}:9060/ || true; ! tr -d \"\\r\" < \"\$headers\" | grep -Fqi \"location: http://invoiceplane.jax22.com\"'"
colmena exec --on "$HOST" -- test -d /srv/appsdata/kaneo/tmp
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:5173/api/health >/dev/null"
colmena exec --on "$HOST" -- "podman exec kaneo env | grep -Fxq 'CUSTOM_OAUTH_CLIENT_ID=kaneo'"
colmena exec --on "$HOST" -- "podman exec kaneo env | grep -Fxq 'S3_BUCKET=kaneo-uploads'"
colmena exec --on "$HOST" -- "sudo -u postgres psql -d kaneo -tAc 'select 1' | tr -d '[:space:]' | grep -Fxq 1"
colmena exec --on "$HOST" -- test -d /srv/appsdata/listmonk/uploads
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9000/admin/login | grep -Fq 'Authentik'"
if [ "$SKIP_OUTLINE_SMOKE" != 1 ]; then
  colmena exec --on "$HOST" -- test -d /srv/appsdata/outline/redis
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9050/_health | grep -Fxq OK"
  colmena exec --on "$HOST" -- "podman exec outline env | grep -Fxq 'OIDC_CLIENT_ID=outline'"
  colmena exec --on "$HOST" -- "podman exec outline env | grep -Fxq 'FILE_STORAGE=s3'"
  colmena exec --on "$HOST" -- "podman exec outline env | grep -Fxq 'AWS_S3_UPLOAD_BUCKET_NAME=outline-uploads'"
  colmena exec --on "$HOST" -- "podman exec outline env | grep -Fxq 'AWS_S3_UPLOAD_BUCKET_URL=https://garage.jax22.com'"
  colmena exec --on "$HOST" -- "sudo -u postgres psql -d outline -tAc 'select 1' | tr -d '[:space:]' | grep -Fxq 1"
fi
colmena exec --on "$HOST" -- test -d /srv/appsdata/plane
colmena exec --on "$HOST" -- test -d /srv/appsdata/plane/rabbitmq
colmena exec --on "$HOST" -- test -d /srv/appsdata/plane/redis
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9020/api/instances/ >/dev/null"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9020/god-mode/ | grep -Eiq 'plane|root|script'"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9020/spaces/ | grep -Eiq 'plane|root|script'"
colmena exec --on "$HOST" -- "podman exec plane-api env | grep -Fxq 'POSTGRES_DB=plane'"
colmena exec --on "$HOST" -- "podman exec plane-api env | grep -Fxq 'REDIS_PORT=6381'"
colmena exec --on "$HOST" -- "podman exec plane-api env | grep -Fxq 'USE_MINIO=0'"
colmena exec --on "$HOST" -- "podman exec plane-api env | grep -Fxq 'AWS_REGION=garage'"
colmena exec --on "$HOST" -- "podman exec plane-api env | grep -Fxq 'AWS_S3_BUCKET_NAME=plane-uploads'"
colmena exec --on "$HOST" -- "podman exec plane-api env | grep -Fxq 'AWS_S3_ENDPOINT_URL=https://garage.jax22.com'"
colmena exec --on "$HOST" -- "podman exec plane-api python manage.py shell -c 'from io import BytesIO; from plane.settings.storage import S3Storage; storage = S3Storage(); name = \"smoke/plane-garage-storage-smoke.txt\"; data = b\"plane-garage-storage-smoke\"; storage.delete_files([name]); assert storage.upload_file(BytesIO(data), name, content_type=\"text/plain\"); assert storage.get_object_metadata(name)[\"ContentLength\"] == len(data); body = storage.s3_client.get_object(Bucket=storage.aws_storage_bucket_name, Key=name)[\"Body\"].read(); assert body == data; assert storage.delete_files([name]); assert storage.get_object_metadata(name) is None'"
colmena exec --on "$HOST" -- "sudo -u postgres psql -d plane -tAc 'select 1' | tr -d '[:space:]' | grep -Fxq 1"
colmena exec --on "$HOST" -- "sudo -u postgres psql -d plane -tAc 'select count(*) > 0 from instance_admins' | tr -d '[:space:]' | grep -Fxq t"
colmena exec --on "$HOST" -- test -d /srv/appsdata/postiz/uploads
colmena exec --on "$HOST" -- test -d /srv/appsdata/postiz/postgresql
colmena exec --on "$HOST" -- test -d /srv/appsdata/postiz/redis
colmena exec --on "$HOST" -- test -d /srv/appsdata/postiz/temporal/elasticsearch
colmena exec --on "$HOST" -- test -d /srv/appsdata/postiz/temporal/postgresql
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9040/ >/dev/null"
colmena exec --on "$HOST" -- "podman exec postiz env | grep -Fxq 'POSTIZ_GENERIC_OAUTH=true'"
colmena exec --on "$HOST" -- "podman exec postiz env | grep -Fxq 'POSTIZ_OAUTH_CLIENT_ID=postiz'"
colmena exec --on "$HOST" -- "podman exec postiz env | grep -Fxq 'STORAGE_PROVIDER=local'"
colmena exec --on "$HOST" -- "podman exec postiz env | grep -Fxq 'TEMPORAL_ADDRESS=postiz-temporal:7233'"
colmena exec --on "$HOST" -- "podman exec postiz-postgres pg_isready -U postiz -d postiz >/dev/null"
colmena exec --on "$HOST" -- "podman exec postiz-redis redis-cli ping | grep -Fxq PONG"
colmena exec --on "$HOST" -- "podman exec postiz-temporal temporal operator cluster health --address postiz-temporal:7233 >/dev/null"
colmena exec --on "$HOST" -- "podman exec postiz-temporal-elasticsearch curl -fsS --max-time 10 'http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s' >/dev/null"
if [ "$SKIP_SURE_SMOKE" != 1 ]; then
  colmena exec --on "$HOST" -- test -d /srv/appsdata/sure/storage
  colmena exec --on "$HOST" -- test -d /srv/appsdata/sure/redis
  colmena exec --on "$HOST" -- "test \"\$(stat -c '%u:%g' /srv/appsdata/sure/storage)\" = 1000:1000"
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9030/up >/dev/null"
  colmena exec --on "$HOST" -- "sudo -u postgres psql -d sure -tAc 'select 1' | tr -d '[:space:]' | grep -Fxq 1"
  colmena exec --on "$HOST" -- "podman exec sure-web env | grep -Fxq 'SELF_HOSTED=true'"
  colmena exec --on "$HOST" -- "podman exec sure-web env | grep -Fxq 'OIDC_CLIENT_ID=sure'"
  colmena exec --on "$HOST" -- "podman exec sure-web env | grep -Fxq 'POSTGRES_DB=sure'"
  colmena exec --on "$HOST" -- "podman exec sure-web env | grep -Fxq 'REDIS_URL=redis://127.0.0.1:6382/1'"
fi
colmena exec --on "$HOST" -- "sh -lc 'findmnt -rn --target /mnt/media >/dev/null || mount /mnt/media'"
colmena exec --on "$HOST" -- test -d /srv/appsdata/metube/state
colmena exec --on "$HOST" -- test -d /mnt/media/downloads/metube
colmena exec --on "$HOST" -- test -d /var/lib/metube-downloads
colmena exec --on "$HOST" -- "sh -lc 'case /var/lib/metube-downloads in /srv/appsdata|/srv/appsdata/*) exit 1 ;; esac'"
colmena exec --on "$HOST" -- "test \"\$(stat -c '%u:%G' /srv/appsdata/metube/state)\" = 1000:testbed"
colmena exec --on "$HOST" -- "test \"\$(stat -c '%u:%G' /var/lib/metube-downloads)\" = 1000:testbed"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:8081/ >/dev/null"
colmena exec --on "$HOST" -- "podman exec --user 1000:1000 metube test -w /downloads"
colmena exec --on "$HOST" -- "podman exec --user 1000:1000 metube test -w /state"
colmena exec --on "$HOST" -- "podman exec --user 1000:1000 metube test -w /temp"
colmena exec --on "$HOST" -- "podman exec metube env | grep -Fxq 'DOWNLOAD_DIR=/downloads'"
colmena exec --on "$HOST" -- "podman exec metube env | grep -Fxq 'STATE_DIR=/state'"
colmena exec --on "$HOST" -- "podman exec metube env | grep -Fxq 'TEMP_DIR=/temp'"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:8025/api/v1/messages >/dev/null"
colmena exec --on "$HOST" -- "podman exec fizzy env | grep -Fxq 'SMTP_USERNAME=fizzy'"
colmena exec --on "$HOST" -- "python3 -c 'import email.message, smtplib; msg = email.message.EmailMessage(); msg[\"Subject\"] = \"testbed SMTP AUTH smoke\"; msg[\"From\"] = \"fizzy@testbed.home.arpa\"; msg[\"To\"] = \"test@example.com\"; msg.set_content(\"testbed SMTP AUTH smoke\"); smtp = smtplib.SMTP(\"127.0.0.1\", 1025, timeout=5); smtp.login(\"fizzy\", \"mailpit\"); smtp.send_message(msg); smtp.quit()'"
colmena exec --on "$HOST" -- "sudo -u postgres psql -d listmonk -tAc \"select (value->>'enabled') from settings where key = 'security.oidc'\" | tr -d '[:space:]' | grep -Fxq true"

printf 'Checking backup and restore validation...\n'
colmena exec --on "$HOST" -- "sh -lc 'findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups'"
colmena exec --on "$HOST" -- systemctl start testbed-appdata-backup.service
colmena exec --on "$HOST" -- systemctl start testbed-appdata-restore-check.service
colmena exec --on "$HOST" -- /etc/fleet/testbed-recovery-verify

printf 'Checking Gateway-routed Listmonk URLs when reachable from this environment...\n'
colmena exec --on gateway-vm -- "sh -lc 'status=000; for attempt in \$(seq 1 12); do status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve affine.jax22.com:443:127.0.0.1 https://affine.jax22.com/); case \"\$status\" in 2*|30[1278]|401|403) exit 0 ;; esac; sleep 5; done; echo \"unexpected AFFiNE status \$status\" >&2; exit 1'"
colmena exec --on gateway-vm -- "grep -Fq 'https://affine.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:3010/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve gitea.jax22.com:443:127.0.0.1 https://gitea.jax22.com/user/login | grep -Fiq 'authentik'"
colmena exec --on gateway-vm -- "grep -Fq 'https://gitea.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:9070/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve stirling-pdf.jax22.com:443:127.0.0.1 https://stirling-pdf.jax22.com/); case \"\$status\" in 2*|30[1278]|401|403) exit 0 ;; *) echo \"unexpected Stirling PDF status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on gateway-vm -- "grep -Fq 'https://stirling-pdf.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:8086/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve firefly.jax22.com:443:127.0.0.1 https://firefly.jax22.com/); case \"\$status\" in 2*|30[1278]|401|403) exit 0 ;; *) echo \"unexpected Firefly status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on gateway-vm -- "grep -Fq 'https://firefly.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:80/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "sh -lc 'if grep -Fq \"ondemand.jax22.com\" /etc/homepage-dashboard/services.yaml; then exit 1; fi'"
colmena exec --on gateway-vm -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve invoiceplane.jax22.com:443:127.0.0.1 https://invoiceplane.jax22.com/sessions/login); case \"\$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected InvoicePlane auth status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: invoiceplane.h' http://127.0.0.1/sessions/login | grep -Eiq 'invoiceplane|login|password'"
colmena exec --on gateway-vm -- "grep -Fq 'https://invoiceplane.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:9060/sessions/login' /etc/homepage-dashboard/services.yaml"
colmena exec --on monitoring-vm -- "grep -Fq 'invoiceplane.jax22.com' /etc/fleet/checkmate-targets.json"
colmena exec --on gateway-vm -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve fizzy.jax22.com:443:127.0.0.1 https://fizzy.jax22.com/up); case \"\$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected Fizzy auth status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: fizzy.h' http://127.0.0.1/up >/dev/null"
colmena exec --on gateway-vm -- "grep -Fq 'https://fizzy.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:9010/up' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve keeper.jax22.com:443:127.0.0.1 https://keeper.jax22.com/); case \"\$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected Keeper auth status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on gateway-vm -- "grep -Fq 'https://keeper.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:3000/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve homebox.jax22.com:443:127.0.0.1 https://homebox.jax22.com/api/v1/status | grep -Fq '\"health\":true'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: homebox.h' http://127.0.0.1/api/v1/status | grep -Fq '\"health\":true'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/homebox/.well-known/openid-configuration | grep -Fq '\"issuer\"'"
colmena exec --on gateway-vm -- "sh -lc 'headers=\$(mktemp); body=\$(mktemp); trap \"rm -f \\\"\$headers\\\" \\\"\$body\\\"\" EXIT; status=\$(curl -sS -D \"\$headers\" -o \"\$body\" -w \"%{http_code}\" --max-time 10 --resolve homebox.jax22.com:443:127.0.0.1 https://homebox.jax22.com/api/v1/users/login/oidc); test \"\$status\" = 302; tr -d \"\\r\" < \"\$headers\" | grep -Fqi \"location: https://auth.jax22.com/application/o/authorize/\"; tr -d \"\\r\" < \"\$headers\" | grep -Fq \"redirect_uri=https%3A%2F%2Fhomebox.jax22.com%2Fapi%2Fv1%2Fusers%2Flogin%2Foidc%2Fcallback\"; ! tr -d \"\\r\" < \"\$headers\" | grep -Fq \"redirect_uri=https%3A%2F%2Fhttps\"; tr -d \"\\r\" < \"\$headers\" | grep -Fq \"Domain=homebox.jax22.com\"; ! tr -d \"\\r\" < \"\$headers\" | grep -Fq \"Domain=https\"'"
colmena exec --on gateway-vm -- "grep -Fq 'https://homebox.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:7745/api/v1/status' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve kaneo.jax22.com:443:127.0.0.1 https://kaneo.jax22.com/api/health >/dev/null"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: kaneo.h' http://127.0.0.1/api/health >/dev/null"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/kaneo/.well-known/openid-configuration | grep -Fq '\"issuer\"'"
colmena exec --on gateway-vm -- "sh -lc 'body=\$(mktemp); trap \"rm -f \\\"\$body\\\"\" EXIT; status=\$(curl -sS -o \"\$body\" -w \"%{http_code}\" --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 \"https://auth.jax22.com/application/o/authorize/?client_id=kaneo&redirect_uri=https%3A%2F%2Fkaneo.jax22.com%2Fapi%2Fauth%2Foauth2%2Fcallback%2Fcustom&response_type=code&scope=openid%20profile%20email&state=test&nonce=test\"); case \"\$status\" in 2*|3*) ;; *) echo \"unexpected Kaneo authorize status \$status\" >&2; cat \"\$body\" >&2; exit 1 ;; esac; ! grep -Eiq \"invalid[ _-]*(client|redirect)\" \"\$body\"'"
colmena exec --on gateway-vm -- "grep -Fq 'https://kaneo.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:5173/api/health' /etc/homepage-dashboard/services.yaml"
if [ "$SKIP_KARAKEEP_SMOKE" != 1 ]; then
  colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve karakeep.jax22.com:443:127.0.0.1 https://karakeep.jax22.com/ >/dev/null"
  colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: karakeep.h' http://127.0.0.1/ >/dev/null"
  colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/karakeep/.well-known/openid-configuration | grep -Fq '\"issuer\"'"
  colmena exec --on gateway-vm -- "grep -Fq 'https://karakeep.jax22.com/' /etc/homepage-dashboard/services.yaml"
  colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:9090/' /etc/homepage-dashboard/services.yaml"
  colmena exec --on monitoring-vm -- "grep -Fq 'karakeep.jax22.com' /etc/fleet/checkmate-targets.json"
fi
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve listmonk.jax22.com:443:127.0.0.1 https://listmonk.jax22.com/admin/login | grep -Fq 'Authentik'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: listmonk.h' http://127.0.0.1/admin/login | grep -Fq 'Authentik'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/listmonk/.well-known/openid-configuration | grep -Fq '\"issuer\"'"
if [ "$SKIP_OUTLINE_SMOKE" != 1 ]; then
  colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve outline.jax22.com:443:127.0.0.1 https://outline.jax22.com/_health | grep -Fxq OK"
  colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: outline.h' http://127.0.0.1/_health | grep -Fxq OK"
  colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/outline/.well-known/openid-configuration | grep -Fq '\"issuer\"'"
  colmena exec --on gateway-vm -- "sh -lc 'body=\$(mktemp); trap \"rm -f \\\"\$body\\\"\" EXIT; status=\$(curl -sS -o \"\$body\" -w \"%{http_code}\" --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 \"https://auth.jax22.com/application/o/authorize/?client_id=outline&redirect_uri=https%3A%2F%2Foutline.jax22.com%2Fauth%2Foidc.callback&response_type=code&scope=openid%20profile%20email&state=test&nonce=test\"); case \"\$status\" in 2*|3*) ;; *) echo \"unexpected Outline authorize status \$status\" >&2; cat \"\$body\" >&2; exit 1 ;; esac; ! grep -Eiq \"invalid[ _-]*(client|redirect)\" \"\$body\"'"
  colmena exec --on gateway-vm -- "grep -Fq 'https://outline.jax22.com/' /etc/homepage-dashboard/services.yaml"
  colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:9050/_health' /etc/homepage-dashboard/services.yaml"
fi
colmena exec --on gateway-vm -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve plane.jax22.com:443:127.0.0.1 https://plane.jax22.com/api/instances/); case \"\$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected Plane auth status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on gateway-vm -- "grep -Fq 'https://plane.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:9020/api/instances/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve postiz.jax22.com:443:127.0.0.1 https://postiz.jax22.com/ >/dev/null"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: postiz.h' http://127.0.0.1/ >/dev/null"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/postiz/.well-known/openid-configuration | grep -Fq '\"issuer\"'"
colmena exec --on gateway-vm -- "sh -lc 'body=\$(mktemp); trap \"rm -f \\\"\$body\\\"\" EXIT; status=\$(curl -sS -o \"\$body\" -w \"%{http_code}\" --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 \"https://auth.jax22.com/application/o/authorize/?client_id=postiz&redirect_uri=https%3A%2F%2Fpostiz.jax22.com%2Fsettings&response_type=code&scope=openid%20profile%20email&state=test&nonce=test\"); case \"\$status\" in 2*|3*) ;; *) echo \"unexpected Postiz authorize status \$status\" >&2; cat \"\$body\" >&2; exit 1 ;; esac; ! grep -Eiq \"invalid[ _-]*(client|redirect)\" \"\$body\"'"
colmena exec --on gateway-vm -- "grep -Fq 'https://postiz.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:9040/' /etc/homepage-dashboard/services.yaml"
if [ "$SKIP_SURE_SMOKE" != 1 ]; then
  colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve sure.jax22.com:443:127.0.0.1 https://sure.jax22.com/up >/dev/null"
  colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: sure.h' http://127.0.0.1/up >/dev/null"
  colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/sure/.well-known/openid-configuration | grep -Fq '\"issuer\"'"
  colmena exec --on gateway-vm -- "sh -lc 'body=\$(mktemp); trap \"rm -f \\\"\$body\\\"\" EXIT; status=\$(curl -sS -o \"\$body\" -w \"%{http_code}\" --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 \"https://auth.jax22.com/application/o/authorize/?client_id=sure&redirect_uri=https%3A%2F%2Fsure.jax22.com%2Fauth%2Fopenid_connect%2Fcallback&response_type=code&scope=openid%20profile%20email&state=test&nonce=test\"); case \"\$status\" in 2*|3*) ;; *) echo \"unexpected Sure authorize status \$status\" >&2; cat \"\$body\" >&2; exit 1 ;; esac; ! grep -Eiq \"invalid[ _-]*(client|redirect)\" \"\$body\"'"
  colmena exec --on gateway-vm -- "grep -Fq 'https://sure.jax22.com/' /etc/homepage-dashboard/services.yaml"
  colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:9030/up' /etc/homepage-dashboard/services.yaml"
fi
colmena exec --on gateway-vm -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve metube.jax22.com:443:127.0.0.1 https://metube.jax22.com/); case \"\$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected MeTube auth status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on gateway-vm -- "grep -Fq 'https://metube.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:8081/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "sh -lc 'if grep -Fq \"metube.h\" /etc/homepage-dashboard/services.yaml; then exit 1; fi'"
colmena exec --on monitoring-vm -- "grep -Fq 'metube.jax22.com' /etc/fleet/checkmate-targets.json"
colmena exec --on gateway-vm -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve mailpit.jax22.com:443:127.0.0.1 https://mailpit.jax22.com/api/v1/messages); case \"\$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected Mailpit auth status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on gateway-vm -- "python3 -c 'import email.message, smtplib; msg = email.message.EmailMessage(); msg[\"Subject\"] = \"homelab Mailpit SMTP smoke\"; msg[\"From\"] = \"gateway@testbed.home.arpa\"; msg[\"To\"] = \"test@example.com\"; msg.set_content(\"homelab Mailpit SMTP smoke\"); smtp = smtplib.SMTP(\"10.2.20.102\", 25, local_hostname=\"smtp.mailpit.jax22.com\", timeout=5); smtp.login(\"gateway\", \"mailpit\"); smtp.send_message(msg); smtp.quit()'"
colmena exec --on gateway-vm -- "grep -Fq 'https://mailpit.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:8025/api/v1/messages' /etc/homepage-dashboard/services.yaml"

printf 'testbed-vm validation completed.\n'
