(ns yamlstar.parser.prelude
  (:require [clojure.string :as str]))

;; Environment access - returns nil (falsy) when not set
(defn env [key]
  #?(:clj (not-empty (System/getenv key))
     :glj (not-empty (os.Getenv key))))

;; Type checking predicates
(defn is-null? [x] (nil? x))
(defn is-boolean? [x] (or (true? x) (false? x)))
(defn is-number? [x] (number? x))
(defn is-string? [x] (string? x))
(defn is-function? [x] (fn? x))
(defn is-array? [x] (or (vector? x) (seq? x)))
(defn is-object? [x] (map? x))

(defn typeof* [value]
  (cond
    (nil? value) "null"
    (or (true? value) (false? value)) "boolean"
    (number? value) "number"
    (string? value) "string"
    (keyword? value) "string"  ;; Keywords treated as strings
    (symbol? value) "string"   ;; Symbols treated as strings
    (fn? value) "function"
    (or (vector? value) (seq? value)) "array"
    (map? value) "object"
    :else (throw (ex-info "Unknown type" {:value value}))))

;; Sentinel keyword used to retrieve the name from a name*-wrapped function.
;; Only needed for Gloat (JVM uses metadata instead).
#?(:glj (def GET-NAME-SENTINEL :yamlstar/get-name))

;; Look up the trace name of a function.
;; On JVM: reads :trace from function metadata (set by with-meta in name*).
;; On Gloat: calls the function with GET-NAME-SENTINEL (since (meta f) = nil).
(defn func-name [f]
  (when (fn? f)
    #?(:clj (:trace (meta f))
       :glj (try
              (let [result (f GET-NAME-SENTINEL)]
                (when (string? result) result))
              (catch go/any _ nil)))))

;; Creates a named function.
;; On JVM: wraps func with metadata {:trace trace :name name}.
;; On Gloat: returns a multi-arity closure; called with GET-NAME-SENTINEL returns trace.
(defn name* [name func trace]
  #?(:clj (with-meta func {:trace (or trace name) :name name})
     :glj (let [the-trace (or trace name)]
            (fn
              ([a] (if (= a GET-NAME-SENTINEL)
                     the-trace
                     (func a)))
              ([a b] (func a b))
              ([a b c] (func a b c))))))

;; Unicode helpers
(defn from-code-point [cp]
  #?(:clj (String. (int-array [cp]) 0 1)
     :glj (str (char cp))))

;; String helpers
(defn stringify [o]
  (cond
    (= o "\ufeff") "\\uFEFF"
    (fn? o) (str "@" (or (func-name o) "fn"))
    (map? o) (pr-str (keys o))
    (or (vector? o) (seq? o)) (str "[" (str/join "," (map stringify o)) "]")
    (string? o) o
    :else (pr-str o)))

(defn hex-char [chr]
  #?(:clj (format "%x" (int (first chr)))
     :glj (fmt.Sprintf "%x" (int (first chr)))))

;; Debug and error functions
(defn warn [msg]
  #?(:clj (binding [*out* *err*] (println msg))
     :glj (fmt.Fprintln os.Stderr msg)))

(defn die [msg]
  (throw (ex-info msg {})))

(defn die* [msg]
  (die msg))

(defn debug [msg]
  (warn (str ">>> " msg)))

(defn debug-rule [name & args]
  (when (env "DEBUG")
    (let [args-str (str/join "," (map stringify args))]
      (debug (str name "(" args-str ")")))))

(defn FAIL [& args]
  (doseq [o args]
    (prn o))
  (die (str "FAIL '" (or (first args) "???") "'")))

;; Timer (for performance measurement)
(defn timer
  ([] #?(:clj (System/nanoTime) :glj 0))
  ([start] #?(:clj (/ (- (System/nanoTime) start) 1000000000.0) :glj 0.0)))
