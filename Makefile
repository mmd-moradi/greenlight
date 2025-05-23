# Include variables from the .envrc file
include .envrc

# ==================================================================================== #
# HELPERS
# ==================================================================================== #

## help: print this help message
.PHONY: help
help:
	@echo 'Usage:'
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' | sed -e 's/^/ /'

.PHONY: confirm
confirm:
	@echo -n 'Are you sure you want to run this command? (y/n): ' && read ans && [ $${ans:-N} = y ]

# ==================================================================================== #
# DEVELOPMENT
# ==================================================================================== #

## run/api: run the cmd/api application
.PHONY: run/api
run/api:
	@go run ./cmd/api -db-dsn=${GREENLIGHT_DB_DSN}

## db/psql: connect to the database using psql
.PHONY: db/psql
db/psql:
	psql ${GREENLIGHT_DB_DSN}

## db/migrations/new name=$1: create a new database migration
.PHONY: db/migrations/new
db/migration/new:
	@echo 'Creating migration files for ${name}...'
	migrate create -ext=.sql -dir=./migrations -seq ${name}

## db/migrations/up: apply all up database migrations
.PHONY: db/migrations/up
db/migration/up: confirm
	@echo "Running migrations..."
	migrate -path ./migrations -database ${GREENLIGHT_DB_DSN} up

# ==================================================================================== #
# QUALITY CONTROL
# ==================================================================================== #

.PHONY: tidy
tidy:
	@echo 'Formatting .go files...'
	go fmt ./...
	@echo 'Tidying module dependencies...'
	go mod tidy

## audit: run quality control checks
.PHONY: audit
audit:
	@echo 'Checking module dependencies'
	go mod tidy -diff
	go mod verify
	@echo 'Vetting code...'
	go vet ./...
	staticcheck ./...
	@echo 'Running tests...'
	go test -race -vet=off ./...

# ==================================================================================== #
# BUILD
# ==================================================================================== #

## build/api: build the cmd/api application
.PHONY: build/api
build/api:
	@echo 'Building cmd/api...'
	go build -ldflags='-s' -o=./bin/api ./cmd/api
	GOOS=linux GOARCH=amd64 go build -ldflags='-s' -o=./bin/linux_amd64/api ./cmd/api

# ==================================================================================== #
# PRODUCTION
# ==================================================================================== #
production_host_ip = '54.198.247.246'
## production/connect: connect to the production server
.PHONY: production/connect
production/connect:
	ssh greenlight@${production_host_ip} -i ~/.ssh/greenlight.pem


## production/deploy/api: deploy the api to production
.PHONY: production/deploy/api
production/deploy/api:
	rsync -e "ssh -i ~/.ssh/greenlight.pem" -P ./bin/linux_amd64/api greenlight@${production_host_ip}:~
	rsync -e "ssh -i ~/.ssh/greenlight.pem" -rP --delete ./migrations greenlight@${production_host_ip}:~
	rsync -e "ssh -i ~/.ssh/greenlight.pem" -P ./remote/production/api.service greenlight@${production_host_ip}:~
	rsync -e "ssh -i ~/.ssh/greenlight.pem" -P ./remote/production/Caddyfile greenlight@${production_host_ip}:~
	ssh -t -i ~/.ssh/greenlight.pem greenlight@${production_host_ip} '\
	migrate -path ~/migrations -database $$GREENLIGHT_DB_DSN up \
	&& sudo mv ~/api.service /etc/systemd/system/ \
	&& sudo systemctl enable api \
	&& sudo systemctl restart api \
	&& sudo mv ~/Caddyfile /etc/caddy/ \
	&& sudo systemctl reload caddy \
	'
