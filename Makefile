ENV_FILE ?= .env

.PHONY: env-check up down down-v migrate test logs seed doctor check-databases

env-check:
	./scripts/check-env.sh $(ENV_FILE)

up: env-check
	docker compose up -d --build --wait mysql redis s3 mailpit traefik api media-worker

down:
	docker compose down

down-v:
	docker compose down -v

migrate:
	docker compose run --rm workspace pnpm --filter @sonora/api exec prisma migrate deploy

test:
	docker compose run --rm workspace pnpm run ci

logs:
	@if [ -z "$(s)" ]; then echo "usage: make logs s=<service>" >&2; exit 1; fi
	docker compose logs -f $(s)

# The AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY values below are dummy values for the S3Mock emulator, never real credentials.
seed:
	docker compose run --rm -e S3_ENDPOINT=http://s3:9090 -e AWS_ACCESS_KEY_ID=dev -e AWS_SECRET_ACCESS_KEY=dev workspace pnpm --filter @sonora/seed run seed

doctor:
	./scripts/doctor.sh

check-databases:
	./scripts/check-module-databases.sh
