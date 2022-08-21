(let ([scheme-dir (dirname (current-filename))])
  (add-to-load-path scheme-dir)
  (add-to-load-path (string-append scheme-dir "wl/"))
  (add-to-load-path (string-append scheme-dir "winter/")))
