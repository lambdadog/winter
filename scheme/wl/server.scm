(define-module (wl server)
  #:use-module ((wl server internal)
		#:select (make-server
			  server-outputs
			  server-views
			  server-socket
			  run-server)
		#:prefix internal:)
  #:export (make-server
	    server-outputs
	    server-views
	    server-socket
	    run-server))

(define (make-server)
  "Creates a new wayland server."
  (internal:make-server))

(define (server-outputs server)
  "Returns the list of outputs attached to SERVER."
  (internal:server-outputs server))

(define (server-views server)
  "Returns the list of views held by SERVER. This includes unmapped and
disabled views."
  (internal:server-views server))

(define (server-socket server)
  "Returns SERVER's socket name."
  (internal:server-socket server))

(define (run-server server)
  "Runs SERVER. Does not return until SERVER stops."
  (internal:run-server server))
