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

BUILD_NUMBER_FILE := mobile/.build_number
BUILD_NUMBER = $(shell cat $(BUILD_NUMBER_FILE) 2>/dev/null || echo 0)
NEXT_BUILD = $(shell echo $$(($(BUILD_NUMBER) + 1)))

apk:
	@echo $(NEXT_BUILD) > $(BUILD_NUMBER_FILE)
	@echo "Building APK v1.0.$(NEXT_BUILD) (build #$(NEXT_BUILD))..."
	@test -n "$$API_BASE_URL" || { echo "Error: API_BASE_URL env var required"; exit 1; }
	@test -n "$$GOOGLE_CLIENT_ID" || { echo "Error: GOOGLE_CLIENT_ID env var required"; exit 1; }
	cd mobile && flutter build apk --release \
		--build-number=$(NEXT_BUILD) \
		--build-name=1.0.$(NEXT_BUILD) \
		--dart-define=API_BASE_URL=$$API_BASE_URL \
		--dart-define=GOOGLE_CLIENT_ID=$$GOOGLE_CLIENT_ID \
		--dart-define=BUILD_NUMBER=$(NEXT_BUILD)
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
