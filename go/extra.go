package nulldull

import (
	"bytes"
	"encoding/json"
	"reflect"
	"strings"
	"sync"
)

// Extra holds JSON fields the SDK does not model yet. The API adds fields
// without notice; they are kept here and written back by MarshalJSON, so
// nothing is lost when a value is re-encoded.
type Extra map[string]json.RawMessage

var knownFields sync.Map // reflect.Type -> []string

func jsonNames(t reflect.Type) []string {
	if cached, ok := knownFields.Load(t); ok {
		return cached.([]string)
	}
	var names []string
	for i := 0; i < t.NumField(); i++ {
		field := t.Field(i)
		if !field.IsExported() {
			continue
		}
		tag := field.Tag.Get("json")
		if tag == "-" {
			continue
		}
		name, _, _ := strings.Cut(tag, ",")
		if name == "" {
			name = field.Name
		}
		names = append(names, name)
	}
	knownFields.Store(t, names)
	return names
}

// decodeObject decodes data into target (a pointer to a method-less copy of
// the public struct) and collects the unknown fields into extra.
func decodeObject(data []byte, target any, extra *Extra) error {
	if bytes.Equal(bytes.TrimSpace(data), []byte("null")) {
		return nil
	}
	if err := json.Unmarshal(data, target); err != nil {
		return err
	}
	var all map[string]json.RawMessage
	if err := json.Unmarshal(data, &all); err != nil {
		return err
	}
	for _, name := range jsonNames(reflect.TypeOf(target).Elem()) {
		delete(all, name)
	}
	if len(all) == 0 {
		*extra = nil
	} else {
		*extra = all
	}
	return nil
}

// encodeObject encodes value (a method-less copy of the public struct) and
// adds the unknown fields back.
func encodeObject(value any, extra Extra) ([]byte, error) {
	data, err := json.Marshal(value)
	if err != nil || len(extra) == 0 {
		return data, err
	}
	var all map[string]json.RawMessage
	if err := json.Unmarshal(data, &all); err != nil {
		return nil, err
	}
	for name, raw := range extra {
		if _, known := all[name]; !known {
			all[name] = raw
		}
	}
	return json.Marshal(all)
}
