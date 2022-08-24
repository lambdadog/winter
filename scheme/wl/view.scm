(define-module (wl view)
  #:use-module ((wl view internal)
		#:select (view-enable!
			  view-disable!)
		#:prefix internal:)
  #:export (view-enable!
	    view-disable!))

(define (view-enable! view)
  "Enables VIEW."
  (internal:view-enable! view))

(define (view-disable! view)
  "Disables VIEW."
  (internal:view-disable! view))
