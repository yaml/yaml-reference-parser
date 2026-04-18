(ns yamlstar.parser.parser
  (:require [clojure.string :as str]
            [yamlstar.parser.prelude :refer :all]))

;; Forward declarations
(declare auto-detect auto-detect-indent trace-start trace-flush)

;; TRACE flag from environment
(def TRACE
  #?(:clj (Boolean/parseBoolean (or (env "TRACE") "false"))
     :glj (= (os.Getenv "TRACE") "true")))

;; Default state when stack is empty
(def default-state
  {:name nil
   :doc false
   :lvl 0
   :beg 0
   :end nil
   :m nil
   :t nil})

;; Parser state - uses volatiles for mutable state
(defn make-parser [receiver]
  (let [parser {:receiver (volatile! receiver)
                :input (volatile! "")
                :pos (volatile! 0)
                :end (volatile! 0)
                :state (volatile! [])
                :trace-num (volatile! 0)
                :trace-line (volatile! 0)
                :trace-on (volatile! true)
                :trace-off (volatile! 0)
                :trace-info (volatile! ["" "" "" 0])}]
    ;; Link parser to receiver (stores parser directly in the receiver copy, not as atom)
    (vswap! (:receiver parser) assoc :parser parser)
    parser))

;; State management
(defn state-curr [parser]
  (let [state @(:state parser)]
    (if (empty? state)
      default-state
      (peek state))))

(defn state-prev [parser]
  (let [state @(:state parser)]
    (when (>= (count state) 2)
      (nth state (- (count state) 2)))))

(defn state-push [parser name]
  (let [curr (state-curr parser)]
    (vswap! (:state parser) conj
           {:name name
            :doc (:doc curr)
            :lvl (inc (:lvl curr))
            :beg @(:pos parser)
            :end nil
            :m (:m curr)
            :t (:t curr)})))

(defn state-pop [parser]
  (let [child (peek @(:state parser))]
    (vswap! (:state parser) pop)
    (let [curr-state @(:state parser)]
      (when (seq curr-state)
        (vswap! (:state parser)
               (fn [s]
                 (let [curr (peek s)]
                   (conj (pop s)
                         (assoc curr
                                :beg (:beg child)
                                :end @(:pos parser))))))))))

;; Receiver callback routing
(defn make-receivers [parser]
  (let [state @(:state parser)
        names (volatile! [])
        i (volatile! (count state))]
    (while (and (> @i 0)
                (let [n (:name (nth state (dec @i)))]
                  (not (str/includes? (str n) "_"))))
      (vswap! i dec)
      (let [n (:name (nth state @i))]
        (let [n (if-let [[_ c] (re-matches #"chr\((.)\)" (str n))]
                  (str "x" (hex-char c))
                  (str/replace (str n) #"\(.*" ""))]
          (vswap! names #(cons n %)))))
    ;; Decrement i to get actual index (i was count, need count-1)
    (vswap! i dec)
    (if (or (neg? @i) (empty? state))
      {:try nil :got nil :not nil}
      (let [n (:name (nth state @i))
            name (str/join "__" (cons n @names))
            receiver @(:receiver parser)]
        {:try (get-in receiver [:callbacks (str "try__" name)])
         :got (get-in receiver [:callbacks (str "got__" name)])
         :not (get-in receiver [:callbacks (str "not__" name)])}))))

;; Set of anchor rule names that have receiver callbacks.
;; Used for early-exit in receive to avoid expensive make-receivers
;; for the ~85% of calls where no callback will match.
(def ^:private callback-rules
  #{"l_yaml_stream" "ns_yaml_version" "c_tag_handle" "ns_tag_prefix"
    "c_directives_end" "c_document_end" "c_flow_mapping" "c_flow_sequence"
    "l_block_mapping" "l_block_sequence" "ns_l_compact_mapping"
    "ns_l_compact_sequence" "ns_flow_pair" "ns_l_block_map_implicit_entry"
    "c_l_block_map_explicit_entry" "c_ns_flow_map_empty_key_entry"
    "ns_plain" "c_single_quoted" "c_double_quoted" "l_empty"
    "l_nb_literal_text" "c_l_literal" "ns_char" "s_white"
    "s_nb_folded_text" "s_nb_spaced_text" "c_l_folded" "e_scalar"
    "s_l_block_collection" "c_ns_anchor_property" "c_ns_tag_property"
    "c_ns_alias_node"})

(defn receive [parser func type pos]
  ;; Early exit: find the anchor rule name (first name with _)
  ;; and check if it has any callbacks.
  (let [state @(:state parser)]
    (when (seq state)
      (let [anchor-name (loop [i (dec (count state))]
                          (when (>= i 0)
                            (let [n (:name (nth state i))]
                              (if (and n (str/includes? (str n) "_"))
                                (str n)
                                (recur (dec i))))))]
        (when (and anchor-name (callback-rules anchor-name))
          (let [receivers (make-receivers parser)
                receiver-fn (get receivers type)]
            (when receiver-fn
              (let [curr-pos @(:pos parser)
                    input @(:input parser)
                    text (if (<= pos curr-pos)
                           (subs input pos curr-pos)
                           "")]
                (receiver-fn @(:receiver parser)
                             {:text text
                              :state (state-curr parser)
                              :start pos})))))))))

;; Forward declarations for grammar functions
(declare call)

;; The central call mechanism
(defn call
  ([parser func] (call parser func "boolean"))
  ([parser func type]
   (let [[func & args] (if (vector? func) func [func])]
     ;; If func is a number or string, return it directly
     (cond
       (number? func) func
       (string? func) func
       :else
       (do
         (when-not (fn? func)
           (FAIL (str "Bad call type '" (typeof* func) "' for '" func "'")))

         (let [trace (or (func-name func)
                         (:trace (meta func))
                         (str func))]
           (state-push parser trace)

           ;; Set doc flag for l_bare_document
           (when (= trace "l_bare_document")
             (vswap! (:state parser)
                    (fn [s]
                      (let [curr (peek s)]
                        (conj (pop s) (assoc curr :doc true))))))

           ;; Evaluate arguments (skip mapv when no args)
           (let [args (if (nil? args)
                        nil
                        (mapv (fn [a]
                                (cond
                                  (vector? a) (call parser a "any")
                                  (fn? a) (call parser a "any")
                                  :else a))
                              args))
                 pos @(:pos parser)
                 _ (receive parser func :try pos)

                 ;; Call the function — bypass clojure.core/apply
                 ;; when args is empty (common case) to avoid
                 ;; lang.Apply []any allocation and reflection.
                 value (loop [v (if (nil? args)
                                  (func parser)
                                  (apply func parser args))]
                         (if (or (fn? v) (vector? v))
                           (recur (call parser v))
                           v))]

             ;; Type checking - nil is treated as false for boolean type
             (when (and (not= type "any")
                        (not= (typeof* value) type)
                        (not (and (= type "boolean") (nil? value))))
               (FAIL (str "Calling '" trace "' returned '" (typeof* value) "' instead of '" type "'")))

             ;; Handle result
             (if (not= type "boolean")
               nil
               (if value
                 (receive parser func :got pos)
                 (receive parser func :not pos)))

             (state-pop parser)
             value)))))))
;; Special functions - internal versions
(defn start-of-line* [parser]
  (let [pos @(:pos parser)
        input @(:input parser)]
    (or (= pos 0)
        (>= pos @(:end parser))
        (= (nth input (dec pos)) \newline))))

(defn end-of-stream* [parser]
  (>= @(:pos parser) @(:end parser)))

(defn the-end [parser]
  (or (end-of-stream* parser)
      (and (:doc (state-curr parser))
           (start-of-line* parser)
           ;; RE2 doesn't support lookaheads; check manually
           (let [remaining (subs @(:input parser) @(:pos parser))]
             #?(:clj (re-find (re-pattern "^(?:---|\\.\\.\\.)((?=\\s)|$)") remaining)
                :glj (let [prefix (re-find #"^(?:---|\.\.\.)" remaining)]
                       (when prefix
                         (let [after (subs remaining (count prefix))]
                           (or (empty? after)
                               (re-find #"^\s" after))))))))))

;; Grammar-callable versions (return functions)
(defn start-of-line [parser]
  (name* "start_of_line"
    (fn [p] (start-of-line* p))
    "start_of_line"))

(defn end-of-stream [parser]
  (name* "end_of_stream"
    (fn [p] (end-of-stream* p))
    "end_of_stream"))

(defn empty-rule [parser]
  (name* "empty"
    (fn [p] true)
    "empty"))

;; Character matching primitives
(defn chr [parser char]
  (let [trace (str "chr(" (stringify char) ")")
        c (first char)]
    (name* trace
      (fn chr-fn [p]
        (when-not (the-end p)
          (when (= (nth @(:input p) @(:pos p)) c)
            (vswap! (:pos p) inc)
            true)))
      trace)))

(defn rng [parser low high]
  (let [trace (str "rng(" (stringify low) "," (stringify high) ")")
        lo (int (first low))
        hi (int (first high))]
    (name* trace
      (fn rng-fn [p]
        (when-not (the-end p)
          (let [ch (nth @(:input p) @(:pos p))
                cp (int ch)]
            (when (and (>= cp lo) (<= cp hi))
              ;; Advance by 1, plus 1 more for codepoints above U+FFFF
              (when (> cp 65535)
                (vswap! (:pos p) inc))
              (vswap! (:pos p) inc)
              true))))
      trace)))

;; Combinators
(defn all [parser & funcs]
  (name* "all"
    (fn all-fn [p]
      (let [pos @(:pos p)]
        (loop [fs funcs]
          (if (empty? fs)
            true
            (let [f (first fs)]
              (when-not f
                (FAIL "*** Missing function in all group:" funcs))
              (if-not (call p f)
                (do
                  (vreset! (:pos p) pos)
                  false)
                (recur (rest fs))))))))
    "all"))

(defn any [parser & funcs]
  (name* "any"
    (fn any-fn [p]
      (loop [fs funcs]
        (if (empty? fs)
          false
          (if (call p (first fs))
            true
            (recur (rest fs))))))
    "any"))

(defn may [parser func]
  (name* "may"
    (fn may-fn [p]
      (call p func)
      true)
    "may"))

(defn rep [parser min max func]
  (let [trace (str "rep(" min "," max ")")]
    (name* trace
      (fn rep-fn [p]
        (if (and max (< max 0))
          false
          (let [pos-start @(:pos p)]
            (loop [count 0
                   pos @(:pos p)]
              (if (and max (>= count max))
                (if (and (>= count min) (or (nil? max) (<= count max)))
                  true
                  (do
                    (vreset! (:pos p) pos-start)
                    false))
                (if-not (call p func)
                  (if (and (>= count min) (or (nil? max) (<= count max)))
                    true
                    (do
                      (vreset! (:pos p) pos-start)
                      false))
                  (if (= @(:pos p) pos)
                    (if (and (>= count min) (or (nil? max) (<= count max)))
                      true
                      (do
                        (vreset! (:pos p) pos-start)
                        false))
                    (recur (inc count) @(:pos p)))))))))
      trace)))

(defn rep2 [parser min max func]
  (let [trace (str "rep2(" min "," max ")")]
    (name* trace
      (fn rep2-fn [p]
        (if (and max (< max 0))
          false
          (let [pos-start @(:pos p)]
            (loop [count 0
                   pos @(:pos p)]
              (if (and max (>= count max))
                (if (and (>= count min) (or (nil? max) (<= count max)))
                  true
                  (do
                    (vreset! (:pos p) pos-start)
                    false))
                (if-not (call p func)
                  (if (and (>= count min) (or (nil? max) (<= count max)))
                    true
                    (do
                      (vreset! (:pos p) pos-start)
                      false))
                  (if (= @(:pos p) pos)
                    (if (and (>= count min) (or (nil? max) (<= count max)))
                      true
                      (do
                        (vreset! (:pos p) pos-start)
                        false))
                    (recur (inc count) @(:pos p)))))))))
      trace)))

(defn but [parser & funcs]
  (name* "but"
    (fn but-fn [p]
      (when-not (the-end p)
        (let [pos1 @(:pos p)]
          (when (call p (first funcs))
            (let [pos2 @(:pos p)]
              (vreset! (:pos p) pos1)
              (loop [fs (rest funcs)]
                (if (empty? fs)
                  (do
                    (vreset! (:pos p) pos2)
                    true)
                  (if (call p (first fs))
                    (do
                      (vreset! (:pos p) pos1)
                      false)
                    (recur (rest fs))))))))))
    "but"))

(defn chk [parser type expr]
  (let [trace (str "chk(" type "," (stringify expr) ")")]
    (name* trace
      (fn chk-fn [p]
        (let [pos @(:pos p)]
          (when (= type "<=")
            (vswap! (:pos p) dec))
          (let [ok (call p expr)]
            (vreset! (:pos p) pos)
            (if (= type "!")
              (not ok)
              ok))))
      trace)))

(defn case* [parser var map]
  (let [trace (str "case(" var "," (stringify map) ")")]
    (name* trace
      (fn case-fn [p]
        (let [rule (get map var)]
          (when-not rule
            (FAIL (str "Can't find '" var "' in:") map))
          (call p rule)))
      trace)))

(defn flip [parser var map]
  (let [value (get map var)]
    (when-not value
      (FAIL (str "Can't find '" var "' in:") map))
    (if (string? value)
      value
      (call parser value "number"))))

(defn set* [parser var expr]
  (let [trace (str "set('" var "'," (stringify expr) ")")]
    (name* trace
      (fn set-fn [p]
        (let [value (call p expr "any")]
          (if (= value -1)
            false
            (let [value (if (= value "auto-detect")
                          (auto-detect p)
                          value)]
              ;; Update state-prev
              (vswap! (:state p)
                     (fn [s]
                       (if (< (count s) 2)
                         s
                         (let [state-prev (nth s (- (count s) 2))]
                           (assoc s (- (count s) 2)
                                  (assoc state-prev (keyword var) value))))))
              ;; Propagate to parent scopes
              (let [state @(:state p)
                    size (count state)]
                (when (not= (:name (nth state (- size 2))) "all")
                  (loop [i 3]
                    (when (< i size)
                      (let [idx (- size i 1)
                            st (nth state idx)]
                        (vswap! (:state p)
                               (fn [s]
                                 (assoc s idx (assoc st (keyword var) value))))
                        (when-not (= (:name st) "s_l_block_scalar")
                          (recur (inc i))))))))
              true))))
      trace)))

(defn max* [parser max-val]
  (let [trace (str "max(" max-val ")")]
    (name* trace
      (fn max-fn [p] true)
      trace)))

(defn exclude [parser rule]
  (name* "exclude"
    (fn exclude-fn [p] true)
    "exclude"))

(defn add [parser x y]
  (let [trace (str "add(" x "," (stringify y) ")")]
    (name* trace
      (fn add-fn [p]
        (let [y-val (if (fn? y) (call p y "number") y)]
          (when-not (number? y-val)
            (FAIL (str "y is '" (stringify y-val) "', not number in 'add'")))
          (+ x y-val)))
      trace)))

(defn sub [parser x y]
  (let [trace (str "sub(" x "," y ")")]
    (name* trace
      (fn sub-fn [p]
        (- x y))
      trace)))

(defn match [parser]
  (name* "match"
    (fn match-fn [p]
      (let [state @(:state p)]
        (loop [i (dec (count state))]
          (when (> i 0)
            (if (:end (nth state i))
              (let [{:keys [beg end]} (nth state i)
                    input @(:input p)]
                ;; Handle case where beg > end (return empty string like JS)
                (if (<= beg end)
                  (subs input beg end)
                  ""))
              (do
                (when (= i 1)
                  (FAIL "Can't find match"))
                (recur (dec i))))))))
    "match"))

(defn len [parser str-val]
  (name* "len"
    (fn len-fn [p]
      (let [s (if (string? str-val) str-val (call p str-val "string"))]
        (count s)))
    "len"))

(defn ord [parser str-val]
  (name* "ord"
    (fn ord-fn [p]
      (let [s (if (string? str-val) str-val (call p str-val "string"))]
        (- (int (first s)) 48)))
    "ord"))

(defn if* [parser test do-if-true]
  (name* "if"
    (fn if-fn [p]
      (let [test-val (if (instance? Boolean test) test (call p test "boolean"))]
        (if test-val
          (do
            (call p do-if-true)
            true)
          false)))
    "if"))

(defn lt [parser x y]
  (let [trace (str "lt(" (stringify x) "," (stringify y) ")")]
    (name* trace
      (fn lt-fn [p]
        (let [x-val (if (number? x) x (call p x "number"))
              y-val (if (number? y) y (call p y "number"))]
          (< x-val y-val)))
      trace)))

(defn le [parser x y]
  (let [trace (str "le(" (stringify x) "," (stringify y) ")")]
    (name* trace
      (fn le-fn [p]
        (let [x-val (if (number? x) x (call p x "number"))
              y-val (if (number? y) y (call p y "number"))]
          (<= x-val y-val)))
      trace)))

(defn m [parser]
  (name* "m"
    (fn m-fn [p]
      (:m (state-curr p)))
    "m"))

(defn t [parser]
  (name* "t"
    (fn t-fn [p]
      (:t (state-curr p)))
    "t"))

;; Auto-detect indent
(defn auto-detect-indent [parser n]
  (let [pos @(:pos parser)
        input @(:input parser)
        in-seq (and (> pos 0)
                    (re-find #"^[-?:]$" (str (nth input (dec pos)))))
        pattern #"^((?:\ *(?:\#.*)?\n)*)(\ *)"
        match-result (re-find pattern (subs input pos))]
    (when-not match-result
      (FAIL "auto_detect_indent"))
    (let [pre (nth match-result 1)
          m-raw (count (nth match-result 2))
          m (if (and in-seq (zero? (count pre)))
              (if (= n -1) (inc m-raw) m-raw)
              (- m-raw n))
          m (if (< m 0) 0 m)]
      m)))

(defn auto-detect
  "Auto-detect indentation. Can take n as parameter or get it from state."
  ([parser] (auto-detect parser (:m (state-curr parser))))
  ([parser n]
   (let [input @(:input parser)
         pos @(:pos parser)
         pattern #"^.*\n((?:\ *\n)*)(\ *)(.?)"
         match-result (re-find pattern (subs input pos))
         pre (or (nth match-result 1) "")
         m (if (and (nth match-result 3)
                    (pos? (count (nth match-result 3))))
             (- (count (or (nth match-result 2) "")) (or n 0))
             (loop [m 0]
               (if (re-find (re-pattern (str " {" m "}")) pre)
                 (recur (inc m))
                 (- m (or n 0) 1))))]
     (when (and (> m 0)
                (re-find (re-pattern (str "(?m)^.{" (+ m (or n 0)) "} ")) pre))
       (die "Spaces found after indent in auto-detect (5LLU)"))
     (if (zero? m) 1 m))))

;; Main parse function
(defn parse [parser input]
  (let [input (if (or (empty? input) (str/ends-with? input "\n"))
                input
                (str input "\n"))]
    (vreset! (:input parser) input)
    (vreset! (:end parser) (count input))
    (vreset! (:pos parser) 0)
    (vreset! (:state parser) [])

    (when TRACE
      (vreset! (:trace-on parser) (not (trace-start parser))))

    (let [grammar @(requiring-resolve 'yamlstar.parser.grammar/TOP)]
      (try
        (let [ok (call parser grammar)]
          (trace-flush parser)
          (when-not ok
            (throw (ex-info "Parser failed" {})))
          (when (< @(:pos parser) @(:end parser))
            (throw (ex-info "Parser finished before end of input" {})))
          true)
        (catch #?(:clj Exception :glj go/any) e
          (trace-flush parser)
          (throw e))))))

;; Trace support (stubs for now)
(defn trace-start [parser]
  (or (env "TRACE_START") ""))

(defn trace-flush [parser]
  ;; TODO: implement full trace support
  nil)
