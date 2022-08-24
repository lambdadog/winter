(define-module (winter server)
  #:use-module ((wl)
		#:select (bind!)
		#:prefix wl:)
  #:use-module ((wl server)
		#:select (make-server
			  server-outputs
			  server-views
			  server-socket
			  run-server))
  #:use-module ((wl view)
		#:select (view-enable!))
  #:use-module ((ice-9 pretty-print)
		#:select ((pretty-print . pp)))
  #:export (server
	    outputs
	    views
	    run))

(define server
  (make-parameter (make-server)))

(define (outputs)
  (server-outputs (server)))

(define (views)
  (server-views (server)))

(define (run)
  (let ([server (server)])
    (wl:bind! server 'new-output new-output-fn)
    (wl:bind! server 'new-view new-view-fn)
    (display "Running on WAYLAND_DISPLAY=")
    (display (server-socket server))
    (newline)
    (run-server server)))

(define (new-output-fn server output)
  (display "New output: ") (pp output))

(define (new-view-fn server view)
  (display "New view: ") (pp view)
  (wl:bind! view 'map view-map-fn))

(define (view-map-fn view)
  (view-enable! view))
