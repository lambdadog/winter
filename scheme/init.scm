(use-modules (ice-9 pretty-print))

(define (view:on-map-default view)
  "Enable and focus the view when it's mapped."
  (view-enable! view)
  (view-focus! view))

(add-hook! view-map-hooks
	   view:on-map-default)

(define (debug:list-all-views _)
  (display "All views:\n")
  (pretty-print (views)))

(add-hook! view-map-hooks
	   debug:list-all-views)

(define (debug:print-view-name view)
  (display "View name: ")
  (display (view-name view))
  (newline))

(add-hook! view-map-hooks
	   debug:print-view-name)
