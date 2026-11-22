// encoding/base64 from the Go standard library
package main

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"os"
	"strconv"
	"time"
)

func best(iters, reps int, f func()) int64 {
	f()
	f() // warm up
	var min int64 = 1 << 62
	for i := 0; i < iters; i++ {
		start := time.Now()
		for r := 0; r < reps; r++ {
			f()
		}
		if ns := time.Since(start).Nanoseconds(); ns < min {
			min = ns
		}
	}
	return min / int64(reps)
}

func main() {
	size, _ := strconv.Atoi(os.Args[1])
	iters, _ := strconv.Atoi(os.Args[2])
	// Each sample times enough calls to cover 256 KiB, for timer resolution
	reps := max(1, (262144+size-1)/size)
	data := make([]byte, size)
	for i := range data {
		data[i] = byte((i*31 + 7) % 256)
	}
	text := base64.StdEncoding.EncodeToString(data)
	decoded, err := base64.StdEncoding.DecodeString(text)
	if err != nil || !bytes.Equal(decoded, data) {
		panic("round trip failed")
	}
	var sink int
	enc := best(iters, reps, func() { sink += len(base64.StdEncoding.EncodeToString(data)) })
	dec := best(iters, reps, func() {
		out, _ := base64.StdEncoding.DecodeString(text)
		sink += len(out)
	})
	fmt.Println(enc, dec)
	if sink == 0 {
		fmt.Fprintln(os.Stderr, sink)
	}
}
