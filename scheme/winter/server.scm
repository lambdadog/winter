(define-module (winter server)
  ;; #:use-module ((wl)
  ;; 		#:select (bind)
  ;; 		#:prefix wl:)
  #:use-module ((wl server)
		#:select (make-server
			  server-socket
			  run-server))
  #:export (run))

(define server
  (make-parameter (make-server)))

(define (run)
  (let ([server (server)])
    (display "Running on WAYLAND_DISPLAY=")
    (display (server-socket server))
    (newline)
    (run-server server)))
