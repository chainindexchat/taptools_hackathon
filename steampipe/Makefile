BUILD_TAGS = netgo

# Extract TAPTOOLS_API_KEY from .env
TAPTOOLS_API_KEY ?= $(shell grep -E '^TAPTOOLS_API_KEY=' .env | cut -d '=' -f2-)

install:
	go build -o ~/.steampipe/plugins/hub.steampipe.io/plugins/turbot/taptools@latest/steampipe-plugin-taptools.plugin -tags "${BUILD_TAGS}" -ldflags "-X 'taptools.APIKey=${TAPTOOLS_API_KEY}'" *.go

.PHONY: install