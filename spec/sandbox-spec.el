
;; "characterization tests"
(describe "sandbox"
  (it "returns nil when passed the empty list"
    (should (null (sandbox '()))))

  (it "rewrites any function as a function with a prefix"
    (should (equal (sandbox '(hi t))
                   '(emacs-sandbox-hi t))))

  (it "allows t, nil, &rest, &optional..."
    (should (equal (sandbox '(t nil &rest &optional))
                   '(t nil &rest &optional))))

  (it "passes a quoted form along as quoted"
    ;; should this be a preference?
    (should (equal (sandbox ''(hi t))
                   (quote (quote (hi t)))))))

(describe "sandbox--check-args"
  (it "is true for an empty list"
    (should (equal t (sandbox--check-args nil))))

  (it "is true for a list with a single symbol"
    (should (equal t (sandbox--check-args '(wtf)))))

  (it "is true for a list with multiple symbols"
    (should (equal t (sandbox--check-args '(wtf omg)))))

  (it "is false for a list with symbols where one is bound"
    (let ((omg 10))
      (should (sandbox--check-args '(wtf omg))))))


(describe "sandbox--safe-length-args-p"
  (it "is true for a small list"
    (should (sandbox--safe-length-args-p '(1 2 3) 0 100)))

  (it "is false if the list is too long"
    (should-not (sandbox--safe-length-args-p '(1 2 3) 0 1)))

  (it "should count sub-lists as lists"
    (should (sandbox--safe-length-args-p '((2 3) 2 5 6 7 ) 0 4))
    (should-not (sandbox--safe-length-args-p '((2 3) 2) 0 2))))

(describe "sandbox-defun"
  (it "makes functions in the sandboxed namespace"
    (progn
      (sandbox-defun testfn (one two) (+ one two))
      (should (eq 3 (emacs-sandbox-testfn 1 2)))))
  (it "handles functions with docstrings too"
    (progn
      (sandbox-defun testfn (one two) "test function" (+ one two))
      (should (eq 3 (emacs-sandbox-testfn 1 2))))))


(describe "sandbox-while"
  (it "wont allow infinite looping"
    (should-error
     (let ((i 0))
       (sandbox-while t (incf i))))))

(describe "sandbox-def-unbound-fns"
  (it "defines sandboxed functions if they aren't defined yet"
    (progn
      (fmakunbound 'emacs-sandbox-progn)
      (fmakunbound 'emacs-sandbox-defun)
      (fmakunbound 'emacs-sandbox-+)
      (sandbox-def-unbound-fns
       '(emacs-sandbox-progn
         (emacs-sandbox-defun emacs-sandbox-testsum (emacs-sandbox-one emacs-sandbox-two) (emacs-sandbox-+ emacs-sandbox-one emacs-sandbox-two))
         (emacs-sandbox-testsum 1 2)))
      (should (eq t (and (fboundp 'emacs-sandbox-progn)
                         (fboundp 'emacs-sandbox-defun)
                         (fboundp 'emacs-sandbox-+))))))
  (it "also has a macro"
    (progn
      (fmakunbound 'emacs-sandbox-progn)
      (fmakunbound 'emacs-sandbox-defun)
      (fmakunbound 'emacs-sandbox-+)
      (sandbox-define-unbound-functions
            (emacs-sandbox-progn
             (emacs-sandbox-defun emacs-sandbox-testsum (emacs-sandbox-one emacs-sandbox-two) (emacs-sandbox-+ emacs-sandbox-one emacs-sandbox-two))
             (emacs-sandbox-testsum 1 2)))
      (should (eq t (and (fboundp 'emacs-sandbox-progn)
                         (fboundp 'emacs-sandbox-defun)
                         (fboundp 'emacs-sandbox-+))))))
  (it "will use predefined functions if available"
    (progn
      (fmakunbound 'emacs-sandbox-defun)
      (defmacro emacs-sandbox-defun (fcn args &rest body)
        `(sandbox-defun ,fcn ,args ,body))
      (sandbox-def-unbound-fns
       '(emacs-sandbox-progn
         (emacs-sandbox-defun emacs-sandbox-testsum (emacs-sandbox-one emacs-sandbox-two)
                              (emacs-sandbox-+ emacs-sandbox-one emacs-sandbox-two))
        (emacs-sandbox-testsum 1 2)))
      (should-not (equal #'emacs-sandbox-defun #'defun)))))

(describe "sandbox-eval"
  (it "will eval defuns in a different namespace"
      (should (eq 3
                  (progn
                    (let ((expression '(progn
                                         (defun testfn (one two) (+ one two))
                                         (testfn 1 2))))
                      (sandbox-def-unbound-fns (sandbox expression))
                      (sandbox-eval expression)))))))

(describe "sandbox-eval-with-bindings"
  (it "runs stuff coming out of the sandbox"
    (should (eq 3 (sandbox-eval-with-bindings (progn
                                                (defun testfn (one two)
                                                  (+ one two))
                                                (testfn 1 2))))))
  (it "should not break out of the sandbox"
    (progn
      (sandbox-eval-with-bindings (progn
                                    (defmacro my-defun (fcn args &rest body)
                                      `(,(intern "defun") ,fcn ,args ,body))
                                    (my-defun outside-sandbox ()
                                              (message "If this test does not pass, I've been defined outside the sandbox")
                                              t)))
      (should
       (and (not (fboundp 'outside-sandbox))
            (fboundp 'emacs-sandbox-outside-sandbox))))))

;; actual spec tests
(describe "sandbox"
  (it "forbids the user from executing the bad stuff"
    (with-mock2
      (defmock a-sensitive-function ())
      (should-error
       (eval (sandbox '(a-sensitive-function)))

       :type 'void-function)
      (should (= 0 (el-spec:called-count 'a-sensitive-function)))))

  (it "allows the user to execute the good stuff"
    (with-mock2
      (defmock emacs-sandbox-not-sensitive ())
      (eval (sandbox '(not-sensitive)))
                (should (= 1 (el-spec:called-count 'emacs-sandbox-not-sensitive))))))


(describe "an infinite loop condition"
  (it "cant allow looping, i guess"
    (should-error
     (eval (sandbox '(while t
                       (throw 'omg-should-not-even-be-allowed-to-run!!!)))))
    :type 'void-function)

  (it "wont loop forever with sandbox-eval"
    (should-error
     (sandbox-eval (sandbox '(while t (setq what-doing "looping")))))))

(describe "user trying to access an outside variable"
  (it "doesnt work"
    (let ((a-secret 'shhhhh))
      (should-error
       (eval (sandbox '(message a-secret)))

       :type 'void-variable
       )

      )
    ))

;;;;;;;;;;;;;;;;
;; need two types of specs to advance:
;; the first is examples of
;;
