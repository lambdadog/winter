(define-module (wl)
  #:use-module ((wl internal)
		#:select (bind!)
		#:prefix internal:)
  #:export (bind!))

(define (bind! wl-object event function)
  "Binds FUNCTION to EVENT of WL-OBJECT."
  (internal:bind! wl-object event function))
