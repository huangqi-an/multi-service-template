// hello-api —— 用来验证 nginx -> web-net -> 业务容器 这条链路的最小服务。
//
// 只依赖标准库，两个用途：
//   - 证明入口层能把请求正确转发并剥掉路径前缀；
//   - 作为 Go 版服务的「照着抄」起点。
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

// helloResponse 是 / 的返回体。
type helloResponse struct {
	Service   string `json:"service"`
	Message   string `json:"message"`
	Container string `json:"container"`
	Time      string `json:"time"`
}

func main() {
	// 容器 hostname 取的是容器 ID，用来确认请求实际落在哪个实例上
	hostname, err := os.Hostname()
	if err != nil {
		hostname = "unknown"
	}

	mux := http.NewServeMux()

	// "GET /{$}" 是 Go 1.22 起支持的模式语法：{$} 表示路径必须到此结束，
	// 所以它只匹配 "/" 本身，不会像 "/" 那样把 /nothere 也一并吃掉。
	// 少了 {$}，后端永远不会返回 404，「前缀是否剥对」也就验不出来了。
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, helloResponse{
			Service:   "hello-api",
			Message:   "入口层到业务服务的链路已打通",
			Container: hostname,
			Time:      time.Now().UTC().Format(time.RFC3339),
		})
	})

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]string{"status": "ok"})
	})

	srv := &http.Server{
		Addr:    ":8000",
		Handler: withAccessLog(mux),
		// 只设读头超时：防止慢连接长期占着 goroutine，又不影响正常请求
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("hello-api 监听 :8000，容器 %s", hostname)
	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}

// withAccessLog 打印每个请求的方法、路径、状态码和耗时。
//
// 作用不只是"有日志"：记录的是**后端实际收到的路径**，
// 所以 /hello/a 经入口层转发后，这里会显示 GET /a —— 前缀有没有被剥掉，
// 看日志比看响应码更直接。标准库默认不打访问日志，需要自己包一层。
func withAccessLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s -> %d (%s)", r.Method, r.URL.Path, rec.status, time.Since(start).Round(time.Millisecond))
	})
}

// statusRecorder 包裹 ResponseWriter，只为了记下 WriteHeader 传出的状态码。
// 没显式调用 WriteHeader 时默认 200，所以初始值设为 200。
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// writeJSON 统一处理响应头与序列化；编码失败时握手已经发出，只能记日志。
func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("写响应失败: %v", err)
	}
}
