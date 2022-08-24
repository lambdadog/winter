(define-module (winter server)
  #:use-module ((wl)
		#:select (bind!)
		#:prefix wl:)
  #:use-module ((wl server)
		#:select (make-server
			  server-socket
			  run-server))
  #:use-module ((ice-9 pretty-print)
		#:select ((pretty-print . pp)))
  #:export (run))

(define server
  (make-parameter (make-server)))

(define (run)
  (let ([server (server)])
    (wl:bind! server 'new-output new-output-fn)
    (display "Running on WAYLAND_DISPLAY=")
    (display (server-socket server))
    (newline)
    (run-server server)))

(define (new-output-fn server output)
  (display "New output: ") (pp output))
