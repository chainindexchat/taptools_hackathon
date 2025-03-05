package main

import (
	"steampipe/taptools"

	"github.com/joho/godotenv"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin"
)

func main() {

	_ = godotenv.Load()

	plugin.Serve(&plugin.ServeOpts{PluginFunc: taptools.Plugin})
}
