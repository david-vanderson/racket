#lang racket/unit

(require "../../utils/utils.rkt"
         "signatures.rkt"
         "utils.rkt"
         syntax/parse racket/match 
         syntax/parse/experimental/reflect
         (typecheck signatures tc-funapp)
         (types utils)
         (private syntax-properties)
         (rep type-rep filter-rep object-rep))

(import tc-expr^ tc-app-keywords^
        tc-app-hetero^ tc-app-list^ tc-app-apply^ tc-app-values^
        tc-app-objects^ tc-app-eq^ tc-app-lambda^ tc-app-special^)
(export tc-app^)


(define-syntax-class annotated-op
  (pattern i:identifier
           #:when (or (type-inst-property #'i) 
                      (type-ascription-property #'i))))

(define-tc/app-syntax-class (tc/app-annotated expected)
  ;; Just do regular typechecking if we have one of these.
  (pattern (~and form (rator:annotated-op . rands))
    (tc/app-regular #'form expected)))

(define-tc/app-syntax-class (tc/app-regular* expected)
  (pattern form (tc/app-regular #'form expected)))

(define-syntax-rule (combine-tc/app-syntax-classes class-name case ...)
  (define-syntax-class (class-name expected)
    #:attributes (check)
    (pattern (~reflect v (case expected) #:attributes (check))
             #:attr check (attribute v.check)) ...))

(combine-tc/app-syntax-classes tc/app-special-cases
  tc/app-annotated
  tc/app-list
  tc/app-apply
  tc/app-eq
  tc/app-hetero
  tc/app-values
  tc/app-keywords
  tc/app-objects
  tc/app-lambda
  tc/app-special
  tc/app-regular*)

;; the main dispatching function
;; syntax tc-results/c -> tc-results/c
(define (tc/app/internal form expected)
  (syntax-parse form
    [(#%plain-app . (~var v (tc/app-special-cases expected)))
     ((attribute v.check))]))



;; TODO: handle drest, and filters/objects
(define (arr-matches? arr args)
  (match arr
    [(arr: domain
           (Values: (list (Result: v (FilterSet: (Top:) (Top:)) (Empty:)) ...))
           rest #f (list (Keyword: _ _ #f) ...))
     (cond
       [(< (length domain) (length args)) rest]
       [(= (length domain) (length args)) #t]
       [else #f])]
    [_ #f]))

(define (has-filter? arr)
  (match arr
    [(arr: _ (Values: (list (Result: v (FilterSet: (Top:) (Top:)) (Empty:)) ...))
           _ _ (list (Keyword: _ _ #f) ...)) #f]
    [else #t]))


(define (tc/app-regular form expected)
  (syntax-case form ()
    [(f . args)
     (let* ([f-ty (single-value #'f)]
            [args* (syntax->list #'args)])
       (define (matching-arities arrs)
         (for/list ([arr (in-list arrs)] #:when (arr-matches? arr args*)) arr))
       (define (has-drest/filter? arrs)
         (for/or ([arr (in-list arrs)])
           (or (has-filter? arr) (arr-drest arr))))

       (define arg-tys
         (match f-ty
           [(tc-result1: (Function: (? has-drest/filter?)))
            (map single-value args*)]
           [(tc-result1:
             (Function:
               (app matching-arities
                 (list (arr: doms ranges rests drests _) ..1))))
            (define matching-domains
              (in-values-sequence
                (apply in-parallel
                  (for/list ((dom (in-list doms)) (rest (in-list rests)))
                    (in-sequences (in-list dom) (in-cycle (in-value rest)))))))
            (for/list ([a (in-list args*)] [types matching-domains])
              (match-define (cons t ts) types)
              (if (for/and ((t2 (in-list ts))) (equal? t t2))
                  (tc-expr/check a (ret t))
                  (single-value a)))]
           [_ (map single-value args*)]))
       (tc/funapp #'f #'args f-ty arg-tys expected))]))

;(trace tc/app/internal)

;; syntax -> tc-results
(define (tc/app form) (tc/app/internal form #f))

;; syntax tc-results/c -> tc-results/c
(define (tc/app/check form expected) (tc/app/internal form expected))
