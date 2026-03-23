.PHONY: up down build migrate seed load-seed seed-export seed-import shell test lint apk

up:
	docker-compose up -d

down:
	docker-compose down

build:
	docker-compose build

migrate:
	docker-compose exec web python manage.py migrate

seed:
	docker-compose exec web python manage.py seed_lookups
	docker-compose exec web python manage.py seed_superusers
	docker-compose exec web python manage.py seed_rbac

load-seed:
	docker-compose exec web python manage.py load_seed

seed-export:
	@echo "Exporting seed data from local DB..."
	docker-compose exec web bash -c "python manage.py dumpdata \
		--indent 2 \
		--exclude contenttypes \
		--exclude auth.permission \
		--exclude admin.logentry \
		--exclude sessions.session \
		--exclude django_celery_results \
		--exclude social_django \
		--exclude users.socialaccount \
		--exclude trips.sippyconversation \
		> /app/seed_data.json"
	docker cp vino-web:/app/seed_data.json ./seed_data.json
	@echo "Exported to seed_data.json"

seed-import:
	@echo "Importing seed data into local DB..."
	docker-compose exec web python manage.py loaddata seed_data.json
	@echo "Done"

shell:
	docker-compose exec web python manage.py shell_plus

test:
	docker-compose exec web pytest -v

lint:
	docker-compose exec web ruff check .
	docker-compose exec web mypy .

BUILD_NUMBER ?= 0

apk:
	@echo "Building APK v1.0.$(BUILD_NUMBER)..."
	cd mobile && flutter build apk --release \
		--dart-define=API_BASE_URL=https://vino-production.up.railway.app \
		--dart-define=GOOGLE_CLIENT_ID=520560916664-27j152ocl7l7ksq3madpf4eb45uplpn7.apps.googleusercontent.com \
		--dart-define=BUILD_NUMBER=$(BUILD_NUMBER)
	@echo "APK built: mobile/build/app/outputs/flutter-apk/app-release.apk"

ECR_BASE ?= {account}.dkr.ecr.us-east-1.amazonaws.com/vino
ENV ?= dev

deploy:
	@if [ "$(ENV)" = "prod" ]; then \
		read -p "Deploy to PROD? Type 'yes' to confirm: " confirm; \
		[ "$$confirm" = "yes" ] || exit 1; \
	fi
	bash scripts/deploy.sh $(ENV)

logs:
	aws logs tail /ecs/vino/$(ENV)/web --follow \
	  --profile vino-$(ENV)

sso-login:
	aws sso login --sso-session gsd
