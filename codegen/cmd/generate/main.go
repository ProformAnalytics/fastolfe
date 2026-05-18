package main

import (
	"context"
	"flag"
	"fmt"
	"log"

	"prolog-sports/codegen/internal/generator"
	"prolog-sports/codegen/internal/loader"
)

func main() {
	csvPath := flag.String("csv", "data/premier-league-data.csv", "path to CSV data file")
	outDir := flag.String("out", "../prolog-engine/data/generated", "output directory for generated .pl files")
	flag.Parse()

	// Swap NewCSVSource for a NewPostgresSource here when moving to production.
	src := loader.NewCSVSource(*csvPath)

	fmt.Printf("Loading matches from %s...\n", *csvPath)
	matches, err := src.LoadMatches(context.Background())
	if err != nil {
		log.Fatalf("load: %v", err)
	}
	fmt.Printf("Loaded %d matches.\n", len(matches))

	fmt.Printf("Generating Prolog facts to %s...\n", *outDir)
	if err := generator.Generate(matches, *outDir); err != nil {
		log.Fatalf("generate: %v", err)
	}
	fmt.Println("Done.")
}
