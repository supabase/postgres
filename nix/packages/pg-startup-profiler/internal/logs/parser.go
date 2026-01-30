package logs

import (
	"time"

	"github.com/supabase/pg-startup-profiler/internal/rules"
)

type Event struct {
	Name       string
	Timestamp  time.Time
	Captures   map[string]string
	Line       string
	MarksReady bool
}

type Parser struct {
	rules *rules.Rules
}

func NewParser(r *rules.Rules) *Parser {
	return &Parser{rules: r}
}

func (p *Parser) ParseLine(line string, events chan<- Event) {
	match := p.rules.Match(line)
	if match != nil {
		events <- Event{
			Name:       match.Pattern.Name,
			Timestamp:  match.Timestamp,
			Captures:   match.Captures,
			Line:       line,
			MarksReady: match.Pattern.MarksReady,
		}
	}
}

func (p *Parser) Reset() {
	p.rules.Reset()
}
