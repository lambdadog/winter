(use-modules (ice-9 pretty-print))

(define (view:on-map-default view)
  "Enable and focus the view when it's mapped."
  (enable-view! view)
  (focus-view! view))

(add-hook! view-on-map-hooks
	   view:on-map-default)

(define (debug:list-all-views _)
  (display "All views:\n")
  (pretty-print (views)))

(add-hook! view-on-map-hooks
	   debug:list-all-views)
