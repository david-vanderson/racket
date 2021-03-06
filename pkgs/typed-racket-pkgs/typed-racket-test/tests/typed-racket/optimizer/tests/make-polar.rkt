#;#;
#<<END
TR opt: make-polar.rkt 30:6 (make-polar 1.0 1.0) -- make-polar
TR opt: make-polar.rkt 30:6 (make-polar 1.0 1.0) -- make-rectangular elimination
TR opt: make-polar.rkt 33:0 (let ((p (+ 1.0+2.0i (make-polar 2.0 4.0)))) (string-append (real->decimal-string (real-part p) 3) (real->decimal-string (imag-part p) 3))) -- unboxed let bindings
TR opt: make-polar.rkt 33:12 1.0+2.0i -- unboxed literal
TR opt: make-polar.rkt 33:21 (make-polar 2.0 4.0) -- make-rectangular elimination
TR opt: make-polar.rkt 33:9 (+ 1.0+2.0i (make-polar 2.0 4.0)) -- unboxed binary float complex
TR opt: make-polar.rkt 34:39 (real-part p) -- complex accessor elimination
TR opt: make-polar.rkt 34:39 (real-part p) -- unboxed unary float complex
TR opt: make-polar.rkt 34:50 p -- leave var unboxed
TR opt: make-polar.rkt 34:50 p -- unbox float-complex
TR opt: make-polar.rkt 34:50 p -- unboxed complex variable
TR opt: make-polar.rkt 35:39 (imag-part p) -- complex accessor elimination
TR opt: make-polar.rkt 35:50 p -- leave var unboxed
TR opt: make-polar.rkt 35:50 p -- unboxed complex variable
END
#<<END
"-0.3070.486"

END

#lang typed/scheme
#:optimize




;; top level
(void (make-polar 1.0 1.0))

;; nested
(let ((p (+ 1.0+2.0i (make-polar 2.0 4.0))))
  (string-append (real->decimal-string (real-part p) 3)
                 (real->decimal-string (imag-part p) 3)))
