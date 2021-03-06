#lang racket/base
(require racket/function
         racket/list
         racket/format
         racket/path
         racket/splicing
         raco/command-name
         setup/dirs
         net/url
         "name.rkt"
         "lib.rkt"
         "commands.rkt"
         (prefix-in setup: setup/setup)
         (for-syntax racket/base))

(define (setup no-setup? setup-collects jobs)
  (unless (or (eq? setup-collects 'skip)
              no-setup?
              (not (member (getenv "PLT_PKG_NOSETUP") '(#f ""))))
    (define installation? (eq? 'installation (current-pkg-scope)))
    (setup:setup
     #:make-user? (not installation?)
     #:avoid-main? (not installation?)
     #:collections (and setup-collects
                        (map (lambda (s)
                               (if (list? s) s (list s)))
                             setup-collects))
     #:tidy? #t
     #:make-doc-index? #t
     #:jobs jobs)))

(define ((pkg-error cmd) . args)
  (apply raise-user-error
         (string->symbol (format "~a ~a" (short-program+command-name) cmd))
         args))


;; Selects scope from `given-scope' through `user' arguments, or infers
;; a scope from `pkgs' if non-#f, and then calls `thunk'.
(define (call-with-package-scope who given-scope scope-dir installation user pkgs pkgs-type thunk)
  (define scope
    (case given-scope
      [(installation user) given-scope]
      [else
       (cond
        [installation 'installation]
        [user 'user]
        [(path-string? given-scope) 
         ;; This can happens when a #:scope value is given a path programmatically.
         ;; Make it easier on clients by alloing that.
         (path->complete-path given-scope)]
        [scope-dir (path->complete-path scope-dir)]
        [else
         (define default-scope (default-pkg-scope))
         (or (and pkgs
                  ;; Infer a scope from given package names:
                  (parameterize ([current-pkg-scope 'user]
                                 [current-pkg-error (pkg-error who)])
                    (with-pkg-lock/read-only
                     (define-values (pkg scope)
                       (for/fold ([prev-pkg #f] [prev-scope #f]) ([pkg (in-list pkgs)])
                         (define pkg-name (package-source->name pkg pkgs-type))
                         (define scope (find-pkg-installation-scope pkg-name))
                         (cond
                          [(not prev-pkg) (values pkg scope)]
                          [(equal? scope prev-scope) (values prev-pkg prev-scope)]
                          [else
                           ((current-pkg-error) 
                            (~a "given packages are installed in different scopes\n"
                                "  package: ~a\n"
                                "  scope: ~a\n"
                                "  second package: ~a\n"
                                "  second scope: ~a")
                            prev-pkg
                            prev-scope
                            pkg
                            scope)])))
                     (when (and scope
                                (not (equal? scope default-scope)))
                       (printf "Inferred package scope: ~a\n" scope))
                     scope)))
             ;; No inference, so use configured default scope:
             default-scope)])]))
  (parameterize ([current-pkg-scope scope]
                 [current-pkg-error (pkg-error who)])
    (thunk)))

(define (catalog->url s)
  (cond
   [(regexp-match? #rx"^[a-zA-Z]*://" s) (string->url s)]
   [else (path->url (path->complete-path s))]))

(splicing-let ()
  (define-syntax (make-commands stx)
    (syntax-case stx ()
      [(_ #:scope-flags (scope-flags ...)
          #:job-flags (job-flags ...)
          #:catalog-flags (catalog-flags ...)
          #:install-type-flags (install-type-flags ...)
          #:install-dep-flags (install-dep-flags ...)
          #:install-dep-desc (install-dep-desc ...)
          #:install-force-flags (install-force-flags ...)
          #:update-deps-flags (update-deps-flags ...)
          #:install-copy-flags (install-copy-flags ...)
          #:install-copy-defns (install-copy-defns ...))
       (with-syntax ([([scope-flags ...]
                       [job-flags ...]
                       [catalog-flags ...]
                       [install-type-flags ...]
                       [(install-dep-flags ... (dep-desc ...))]
                       [install-force-flags ...]
                       [update-deps-flags ...]
                       [install-copy-flags ...]
                       [install-copy-defns ...])
                      (syntax-local-introduce #'([scope-flags ...]
                                                 [job-flags ...]
                                                 [catalog-flags ...]
                                                 [install-type-flags ...]
                                                 [install-dep-flags ...]
                                                 [install-force-flags ...]
                                                 [update-deps-flags ...]
                                                 [install-copy-flags ...]
                                                 [install-copy-defns ...]))])
         #`(commands
            "This tool is used for managing installed packages."
            "pkg-~a-command"
            ;; ----------------------------------------
            [install
             "Install packages"
             #:once-each
             install-type-flags ...
             #:once-any
             [install-dep-flags ...
                                (dep-desc ... 
                                          install-dep-desc ...)]
             [#:bool auto () "Shorthand for `--deps search-auto'"]
             #:once-each
             update-deps-flags ...
             #:once-any
             install-copy-flags ...
             #:once-any
             scope-flags ...
             #:once-each
             catalog-flags ...
             [#:bool skip-installed () ("Skip a <pkg-source> if already installed")]
             install-force-flags ...
             job-flags ...
             #:args pkg-source
             install-copy-defns ...
             (call-with-package-scope
              'install
              scope scope-dir installation user #f a-type
              (lambda ()
                (unless (or (not name) (package-source->name name))
                  ((current-pkg-error) (format "~e is an invalid package name" name)))
                (define setup-collects
                  (with-pkg-lock
                   (parameterize ([current-pkg-catalogs (and catalog
                                                             (list (catalog->url catalog)))])
                     (pkg-install #:dep-behavior (if auto 'search-auto deps)
                                  #:force? force
                                  #:ignore-checksums? ignore-checksums
                                  #:skip-installed? skip-installed
                                  #:update-deps? update-deps
                                  #:strip (or (and source 'source) (and binary 'binary))
                                  #:link-dirs? link-dirs?
                                  (for/list ([p (in-list pkg-source)])
                                    (pkg-desc p a-type name checksum #f))))))
                (setup no-setup setup-collects jobs)))]
            ;; ----------------------------------------
            [update
             "Update packages"
             #:once-each
             [#:bool all ("-a") ("Update all packages if no <pkg-source> is given")]
             [#:bool lookup () "For each name <pkg-source>, look up in catalog"]
             #:once-each
             install-type-flags ...
             #:once-any
             [install-dep-flags ...
                                (dep-desc ... 
                                          install-dep-desc ...)]
             [#:bool auto () "Shorthand for `--deps search-auto' plus `--update-deps'"]
             #:once-each
             update-deps-flags ...
             #:once-any
             install-copy-flags ...
             #:once-any
             scope-flags ...
             #:once-each
             catalog-flags ...
             install-force-flags ...
             job-flags ...
             #:args pkg-source
             install-copy-defns ...
             (call-with-package-scope
              'update
              scope scope-dir installation user pkg-source #f
              (lambda ()
                (define setup-collects
                  (with-pkg-lock
                   (parameterize ([current-pkg-catalogs (and catalog
                                                             (list (catalog->url catalog)))])
                     (pkg-update (for/list ([pkg-source (in-list pkg-source)])
                                   (cond
                                    [lookup
                                     (pkg-desc pkg-source a-type name checksum #f)]
                                    [else
                                     (define-values (pkg-name pkg-type) 
                                       (package-source->name+type pkg-source a-type))
                                     (if (eq? pkg-type 'name)
                                         pkg-name
                                         (pkg-desc pkg-source a-type name checksum #f))]))
                                 #:all? all
                                 #:dep-behavior (if auto 'search-auto deps)
                                 #:force? force
                                 #:ignore-checksums? ignore-checksums
                                 #:update-deps? (or update-deps auto)
                                 #:strip (or (and source 'source) (and binary 'binary))
                                 #:link-dirs? link-dirs?))))
                (setup no-setup setup-collects jobs)))]
            ;; ----------------------------------------
            [remove
             "Remove packages"
             #:once-each
             [#:bool demote () "Demote to auto-installed, instead of removing"]
             [#:bool force () "Remove even if package has dependents"]
             [#:bool auto () "Also remove auto-installed packages that have no dependents"]
             #:once-any
             scope-flags ...
             #:once-each
             job-flags ...
             #:args pkg
             (call-with-package-scope
              'remove
              scope scope-dir installation user pkg 'name
              (lambda ()
                (define setup-collects
                  (with-pkg-lock
                   (pkg-remove pkg
                               #:demote? demote
                               #:auto? auto
                               #:force? force)))
                (setup no-setup setup-collects jobs)))]
            ;; ----------------------------------------
            [show
             "Show information about installed packages"
             #:once-each
             [#:bool all ("-a") "Show auto-installed packages, too"]
             [#:bool dir ("-d") "Show the directory where the package is installed"]
             #:once-any
             scope-flags ...
             [(#:str vers #f) version ("-v") "Show user-specific for installation <vers>"]
             #:args ()
             (define only-mode (case scope
                                 [(installation user) scope]
                                 [else
                                  (cond
                                   [scope-dir (path->complete-path scope-dir)]
                                   [installation 'installation]
                                   [user 'user]
                                   [else (if version 'user #f)])]))
             (for ([mode (if only-mode
                             (list only-mode)
                             (append (let ([main (find-pkgs-dir)])
                                       (reverse
                                        (for/list ([d (get-pkgs-search-dirs)])
                                          (if (equal? d main)
                                              'installation
                                              (simple-form-path d)))))
                                     '(user)))])
               (when (or (equal? mode only-mode) (not only-mode))
                 (unless only-mode
                   (printf "~a\n" (case mode
                                    [(installation) "Installation-wide:"]
                                    [(user) (format "User-specific for installation ~s:"
                                                    (or version (get-installation-name)))]
                                    [else (format "~a:" mode)])))
                 (parameterize ([current-pkg-scope mode]
                                [current-pkg-error (pkg-error 'show)]
                                [current-pkg-scope-version (or version (get-installation-name))])
                   (with-pkg-lock/read-only
                    (pkg-show (if only-mode "" " ")
                              #:auto? all
                              #:directory? dir)))))]
            ;; ----------------------------------------
            [migrate
             "Install packages installed for other version/name"
             #:once-each
             [install-dep-flags ...
                                (dep-desc ... 
                                          "where the default is `search-auto'")]
             #:once-any
             [#:bool source () ("Strip built elements of the package before installing")]
             [#:bool binary () ("Strip source elements of the package before installing")]
             #:once-any
             scope-flags ...
             #:once-each
             catalog-flags ...
             install-force-flags ...
             job-flags ...
             #:args (from-version)
             (call-with-package-scope
              'migrate
              scope scope-dir installation user #f #f
              (lambda ()
                (define setup-collects
                  (with-pkg-lock
                   (parameterize ([current-pkg-catalogs (and catalog
                                                             (list (catalog->url catalog)))])
                     (pkg-migrate from-version
                                  #:dep-behavior deps
                                  #:force? force
                                  #:ignore-checksums? ignore-checksums
                                  #:strip (or (and source 'source) (and binary 'binary))))))
                (setup no-setup setup-collects jobs)))]
            ;; ----------------------------------------
            [create
             "Bundle package from a directory or installed package"
             #:once-any
             [#:bool from-dir () "Treat <directory-or-package> as a directory (the default)"]
             [#:bool from-install () "Treat <directory-or-package> as a package name"]
             #:once-any
             [(#:sym fmt [zip tgz plt] #f) format ()
              ("Select the format of the package to be created;"
               "valid <fmt>s are: zip (the default), tgz, plt")]
             [#:bool manifest () "Creates a manifest file for a directory, rather than an archive"]
             #:once-any
             [#:bool as-is () "Bundle the directory/package as-is (the default)"]
             [#:bool source () "Bundle sources only"]
             [#:bool binary () "Bundle bytecode and rendered documentation without sources"]
             [#:bool built () "Bundle sources, bytecode and rendered documentation"]
             #:once-each
             [(#:str dest-dir #f) dest () "Create output files in <dest-dir>"]
             #:args (directory-or-package)
             (parameterize ([current-pkg-error (pkg-error 'create)])
               (pkg-create (if manifest 'MANIFEST (or format 'zip)) 
                           directory-or-package
                           #:dest (and dest 
                                       (path->complete-path dest))
                           #:source (cond
                                     [from-install 'name]
                                     [else 'dir])
                           #:mode (cond
                                   [source 'source]
                                   [binary 'binary]
                                   [built 'built]
                                   [else 'as-is])))]
            ;; ----------------------------------------
            [config
             "View and modify the package manager's configuration"
             #:once-each
             [#:bool set () "Set <key> to <val> ..."]
             #:once-any
             scope-flags ...
             #:args (key . val)
             (call-with-package-scope
              'config
              scope scope-dir installation user #f #f
              (lambda ()
                (if set
                    (with-pkg-lock
                     (pkg-config #t (cons key val)))
                    (with-pkg-lock/read-only
                     (pkg-config #f (cons key val))))))]
            ;; ----------------------------------------
            [catalog-show
             "Show package information as reported by a catalog"
             #:once-each
             [#:bool all () "Show all packages"]
             [#:bool only-names () "Show only package names"]
             [#:bool modules () "Show implemented modules"]
             catalog-flags ...
             [(#:str vers #f) version ("-v") "Show result for Racket <vers>"]
             #:args pkg-name
             (when (and all (pair? pkg-name))
               ((pkg-error 'catalog-show) "both `--all' and package names provided"))
             (parameterize ([current-pkg-catalogs (and catalog
                                                       (list (catalog->url catalog)))]
                            [current-pkg-error (pkg-error 'catalog-show)]
                            [current-pkg-scope-version (or version
                                                           (current-pkg-scope-version))])
               (pkg-catalog-show pkg-name 
                                 #:all? all
                                 #:only-names? only-names
                                 #:modules? modules))]
            ;; ----------------------------------------
            [catalog-copy
             "Copy/merge package name catalogs"
             #:once-each
             [#:bool from-config () "Include currently configured catalogs last"]
             #:once-any
             [#:bool force () "Force replacement fo existing file/directory"]
             [#:bool merge () "Merge to existing database"]
             #:once-each
             [#:bool override () "While merging, override existing with new"]
             [(#:str vers #f) version ("-v") "Copy information suitable for Racket <vers>"]
             #:args catalog
             (parameterize ([current-pkg-error (pkg-error 'catalog-copy)])
               (when (null? catalog)
                 ((current-pkg-error) "need a destination catalog"))
               (parameterize ([current-pkg-scope-version (or version
                                                             (current-pkg-scope-version))])
                 (pkg-catalog-copy (drop-right catalog 1)
                                   (last catalog)
                                   #:from-config? from-config
                                   #:force? force
                                   #:merge? merge
                                   #:override? override)))]))]))
  (make-commands
   #:scope-flags
   ([(#:sym scope [installation user] #f) scope ()
     ("Select package <scope>, one of"
      "  installation: for all users of the Racket installation"
      "  user: as user-specific for an installation version/name")]
    [#:bool installation ("-i") "Shorthand for `--scope installation'"]
    [#:bool user ("-u") "Shorthand for `--scope user'"]
    [(#:str dir #f) scope-dir () "Select package scope <dir>"])
   #:job-flags
   ([#:bool no-setup () ("Don't run `raco setup' after changing packages (usually"
                         "not a good idea)")]
    [(#:num n #f) jobs ("-j") "Setup with <n> parallel jobs"])
   #:catalog-flags
   ([(#:str catalog #f) catalog () "Use <catalog> instead of configured catalogs"])
   #:install-type-flags
   ([(#:sym type [file dir file-url dir-url github name] #f) type ("-t") 
     ("Type of <pkg-source>;"
      "valid <types>s are: file, dir, file-url, dir-url, github, or name;"
      "if not specified, the type is inferred syntactically")]
    [(#:str name #f) name ("-n") ("Name of package, instead of inferred"
                                  "(makes sense only when a single <pkg-source> is given)")]
    [(#:str checksum #f) checksum () ("Checksum of package, either expected or selected"
                                      "(makes sense only when a single <pkg-source> is given)")])
   #:install-dep-flags
   ([(#:sym mode [fail force search-ask search-auto] #f) deps ()
     ("Specify the behavior for uninstalled dependencies, with"
      "<mode> as one of"
      "  fail: cancels if dependencies are not installed"
      "  force: continues despite missing dependencies"
      "  search-ask: looks for dependencies in the package catalogs"
      "              and asks for permission to auto-install"
      "  search-auto: like `search-ask', but does not ask for permission")])
   #:install-dep-desc
   ("where the default is `search-ask' if <pkg-source> is a package name"
    "or `fail' otherwise")
   #:install-force-flags
   ([#:bool force () "Ignores conflicts"]
    [#:bool ignore-checksums () "Ignores checksums"])
   #:update-deps-flags
   ([#:bool update-deps () "For `search-ask' or `search-auto', also update dependencies"])
   #:install-copy-flags
   ([#:bool link () ("Link a directory package source in place (default for a directory)")]
    [#:bool static-link () ("Link in place, promising collections do not change")]
    [#:bool copy () ("Treat directory sources the same as other sources")]
    [#:bool source () ("Strip package's built elements before installing; implies --copy")]
    [#:bool binary () ("Strip packages' source elements before installing; implies --copy")])
   #:install-copy-defns
   [(define link-dirs? (not (or copy source binary)))
    (define a-type (or (and link 'link) 
                       (and static-link 'static-link)
                       (and (eq? type 'dir) link-dirs? 'link)
                       type))]))
