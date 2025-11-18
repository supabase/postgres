package main

import (
	"github.com/supabase/postgres/pg-ami-builder/cmd"
)

var Version = "dev"

func main() {
	cmd.Version = Version
	cmd.Execute()
}
