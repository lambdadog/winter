(define-module (wl server)
  #:use-module ((wl server internal)
		#:select (make-server
			  server-outputs
			  server-socket
			  run-server)
		#:prefix internal:)
  #:export (make-server
	    server-outputs
	    server-socket
	    run-server))

(define (make-server)
  "Creates a new wayland server."
  (internal:make-server))

(define (server-outputs server)
  "Returns the list of outputs attached to the wayland server."
  (internal:server-outputs server))

(define (server-socket server)
  "Returns the wayland server's socket name."
  (internal:server-socket server))

(define (run-server server)
  "Runs the wayland server passed to it as an argument. Does not
return until the wayland server is stopped."
  (internal:run-server server))
