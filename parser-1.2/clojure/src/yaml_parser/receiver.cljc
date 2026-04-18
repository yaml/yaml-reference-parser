(ns yaml-parser.receiver
  (:require [clojure.string :as str]
            [yaml-parser.prelude :refer :all]
            [yaml-parser.parser :as parser]))

;; Forward declarations
(declare push-event check-document-start check-document-end)

;; Helper: convert hex string to Unicode character string (handles all codepoints)
(defn hex->char [hex-val]
  #?(:clj (let [cp (Integer/parseInt hex-val 16)]
            (if (> cp 65535)
              (String. (Character/toChars cp))
              (str (char cp))))
     :glj (let [[n _] (strconv.ParseInt hex-val 16 32)]
            (str (go/rune n)))))

;; Event constructors
(defn stream-start-event []
  {:event "stream_start"})

(defn stream-end-event []
  {:event "stream_end"})

(defn document-start-event
  ([] (document-start-event false nil))
  ([explicit] (document-start-event explicit nil))
  ([explicit version]
   (cond-> {:event "document_start"}
     explicit (assoc :explicit explicit)
     version (assoc :version version))))

(defn document-end-event
  ([] (document-end-event false))
  ([explicit]
   (cond-> {:event "document_end"}
     explicit (assoc :explicit explicit))))

(defn mapping-start-event
  ([] (mapping-start-event false))
  ([flow]
   {:event "mapping_start"
    :flow flow}))

(defn mapping-end-event []
  {:event "mapping_end"})

(defn sequence-start-event
  ([] (sequence-start-event false))
  ([flow]
   {:event "sequence_start"
    :flow flow}))

(defn sequence-end-event []
  {:event "sequence_end"})

(defn scalar-event [style value]
  (cond-> {:event "scalar"
           :value value}
    (not= style "plain") (assoc :style style)))

(defn alias-event [name]
  {:event "alias"
   :name name})

(defn cache-text [text]
  {:text text})

;; Receiver state
(defn make-receiver []
  {:events (atom [])
   :cache (atom [])
   :anchor (atom nil)
   :tag (atom nil)
   :tag-map (atom {})
   :tag-handle (atom nil)
   :document-start (atom nil)
   :document-end (atom nil)
   :parser (atom nil)
   :in-scalar (atom false)
   :first (atom "")
   :callback (atom nil)
   :callbacks {}})

;; Core receiver operations
(defn send-event [receiver event]
  (if-let [cb @(:callback receiver)]
    (cb event)
    (swap! (:events receiver) conj event)))

(defn add-event [receiver event]
  (let [event (if (:event event)
                (cond-> event
                  @(:anchor receiver) (assoc :anchor @(:anchor receiver))
                  @(:tag receiver) (assoc :tag @(:tag receiver)))
                event)]
    (when (:event event)
      (reset! (:anchor receiver) nil)
      (reset! (:tag receiver) nil))
    (push-event receiver event)
    event))

(defn push-event [receiver event]
  (if (seq @(:cache receiver))
    (swap! (:cache receiver)
           (fn [c]
             (let [last-cache (peek c)]
               (conj (pop c) (conj last-cache event)))))
    (do
      (when (and (:event event)
                 (re-find #"(mapping_start|sequence_start|scalar)" (:event event)))
        (check-document-start receiver))
      (send-event receiver event))))

(defn cache-up
  ([receiver] (cache-up receiver nil))
  ([receiver event]
   (swap! (:cache receiver) conj [])
   (when event
     (add-event receiver event))))

(defn cache-down
  ([receiver] (cache-down receiver nil))
  ([receiver event]
   (let [events (peek @(:cache receiver))]
     (when-not events
       (FAIL "cache_down"))
     (swap! (:cache receiver) pop)
     (doseq [e events]
       (push-event receiver e))
     (when event
       (add-event receiver event)))))

(defn cache-drop [receiver]
  (let [events (peek @(:cache receiver))]
    (when-not events
      (FAIL "cache_drop"))
    (swap! (:cache receiver) pop)
    events))

(defn cache-get [receiver type]
  (let [last-cache (peek @(:cache receiver))]
    (when (and last-cache
               (seq last-cache)
               (= (:event (first last-cache)) type))
      (first last-cache))))

(defn check-document-start [receiver]
  (when-let [doc-start @(:document-start receiver)]
    (send-event receiver doc-start)
    (reset! (:document-start receiver) nil)
    (reset! (:document-end receiver) (document-end-event))))

(defn check-document-end [receiver]
  (when-let [doc-end @(:document-end receiver)]
    (send-event receiver doc-end)
    (reset! (:document-end receiver) nil)
    (reset! (:tag-map receiver) {})
    (reset! (:document-start receiver) (document-start-event))))

;; Unescape maps for double-quoted strings
(def unescapes
  {"\\\\" "\\"
   "\r\n" "\n"
   "\\ " " "
   "\\\"" "\""
   "\\/" "/"
   "\\_" "\u00a0"
   "\\0" "\u0000"
   "\\a" "\u0007"
   "\\b" "\u0008"
   "\\e" "\u001b"
   "\\f" "\u000c"
   "\\n" "\n"
   "\\r" "\r"
   "\\t" "\t"
   "\\\t" "\t"
   "\\v" "\u000b"
   "\\L" "\u2028"
   "\\N" "\u0085"
   "\\P" "\u2029"})

;; Helper for double-quoted string unescaping
(defn unescape-double-quoted [text]
  (let [hex "[0-9a-fA-F]"
        pattern (re-pattern
                  (str "(?:"
                       "\\r\\n"
                       "|(?:\\\\ ?\\r?\\n[ \\t]*)"  ;; end1: line continuation
                       "|(?:[ \\t]*\\r?\\n[ \\t]*)+" ;; end2: folded newlines
                       "|(?:\\\\x(" hex "{2}))"     ;; hex2
                       "|(?:\\\\u(" hex "{4}))"     ;; hex4
                       "|(?:\\\\U(" hex "{8}))"     ;; hex8
                       "|\\\\[\\\\ \"/_0abefnrt\\tvLNP]"
                       ")"))]
    (str/replace text pattern
                 (fn [m]
                   (let [match (if (string? m) m (first m))]
                     (cond
                       ;; hex escapes
                       (re-matches (re-pattern (str "\\\\x(" hex "{2})")) match)
                       (let [[_ hex-val] (re-matches (re-pattern (str "\\\\x(" hex "{2})")) match)]
                         (hex->char hex-val))

                       (re-matches (re-pattern (str "\\\\u(" hex "{4})")) match)
                       (let [[_ hex-val] (re-matches (re-pattern (str "\\\\u(" hex "{4})")) match)]
                         (hex->char hex-val))

                       (re-matches (re-pattern (str "\\\\U(" hex "{8})")) match)
                       (let [[_ hex-val] (re-matches (re-pattern (str "\\\\U(" hex "{8})")) match)]
                         (hex->char hex-val))

                       ;; line continuation
                       (re-matches #"(?:\\ ?\r?\n[ \t]*)" match)
                       ""

                       ;; folded newlines: first newline becomes space, rest become \n
                       (re-matches #"(?:[ \t]*\r?\n[ \t]*)+" match)
                       (let [;; Replace FIRST newline block with empty (fold to space)
                             replaced (str/replace-first match #"[ \t]*\r?\n[ \t]*" "")
                             ;; Replace remaining newline blocks with \n (empty lines)
                             replaced (str/replace replaced #"[ \t]*\r?\n[ \t]*" "\n")]
                         (if (empty? replaced) " " replaced))

                       ;; simple escapes
                       (contains? unescapes match)
                       (get unescapes match)

                       :else match))))))

;; Receiver callbacks
(def receiver-callbacks
  {;; Stream
   "try__l_yaml_stream"
   (fn [receiver o]
     (add-event receiver (stream-start-event))
     (reset! (:tag-map receiver) {})
     (reset! (:document-start receiver) (document-start-event))
     (reset! (:document-end receiver) nil))

   "got__l_yaml_stream"
   (fn [receiver o]
     (check-document-end receiver)
     (add-event receiver (stream-end-event)))

   ;; YAML version
   "got__ns_yaml_version"
   (fn [receiver o]
     (when (:version @(:document-start receiver))
       (die "Multiple %YAML directives not allowed"))
     (swap! (:document-start receiver) assoc :version (:text o)))

   ;; Tag handling
   "got__c_tag_handle"
   (fn [receiver o]
     (reset! (:tag-handle receiver) (:text o)))

   "got__ns_tag_prefix"
   (fn [receiver o]
     (swap! (:tag-map receiver) assoc @(:tag-handle receiver) (:text o)))

   ;; Document markers
   "got__c_directives_end"
   (fn [receiver o]
     (check-document-end receiver)
     (swap! (:document-start receiver) assoc :explicit true))

   "got__c_document_end"
   (fn [receiver o]
     (when @(:document-end receiver)
       (swap! (:document-end receiver) assoc :explicit true))
     (check-document-end receiver))

   ;; Flow mapping
   "got__c_flow_mapping__all__x7b"
   (fn [receiver o]
     (add-event receiver (mapping-start-event true)))

   "got__c_flow_mapping__all__x7d"
   (fn [receiver o]
     (add-event receiver (mapping-end-event)))

   ;; Flow sequence
   "got__c_flow_sequence__all__x5b"
   (fn [receiver o]
     (add-event receiver (sequence-start-event true)))

   "got__c_flow_sequence__all__x5d"
   (fn [receiver o]
     (add-event receiver (sequence-end-event)))

   ;; Block mapping
   "try__l_block_mapping"
   (fn [receiver o]
     (cache-up receiver (mapping-start-event)))

   "got__l_block_mapping"
   (fn [receiver o]
     (cache-down receiver (mapping-end-event)))

   "not__l_block_mapping"
   (fn [receiver o]
     (cache-drop receiver))

   ;; Block sequence
   "try__l_block_sequence"
   (fn [receiver o]
     (cache-up receiver (sequence-start-event)))

   "got__l_block_sequence"
   (fn [receiver o]
     (cache-down receiver (sequence-end-event)))

   "not__l_block_sequence"
   (fn [receiver o]
     (let [events (cache-drop receiver)
           event (first events)]
       (reset! (:anchor receiver) (:anchor event))
       (reset! (:tag receiver) (:tag event))))

   ;; Compact mapping
   "try__ns_l_compact_mapping"
   (fn [receiver o]
     (cache-up receiver (mapping-start-event)))

   "got__ns_l_compact_mapping"
   (fn [receiver o]
     (cache-down receiver (mapping-end-event)))

   "not__ns_l_compact_mapping"
   (fn [receiver o]
     (cache-drop receiver))

   ;; Compact sequence
   "try__ns_l_compact_sequence"
   (fn [receiver o]
     (cache-up receiver (sequence-start-event)))

   "got__ns_l_compact_sequence"
   (fn [receiver o]
     (cache-down receiver (sequence-end-event)))

   "not__ns_l_compact_sequence"
   (fn [receiver o]
     (cache-drop receiver))

   ;; Flow pair
   "try__ns_flow_pair"
   (fn [receiver o]
     (cache-up receiver (mapping-start-event true)))

   "got__ns_flow_pair"
   (fn [receiver o]
     (cache-down receiver (mapping-end-event)))

   "not__ns_flow_pair"
   (fn [receiver o]
     (cache-drop receiver))

   ;; Block map implicit entry
   "try__ns_l_block_map_implicit_entry"
   (fn [receiver o]
     (cache-up receiver))

   "got__ns_l_block_map_implicit_entry"
   (fn [receiver o]
     (cache-down receiver))

   "not__ns_l_block_map_implicit_entry"
   (fn [receiver o]
     (cache-drop receiver))

   ;; Block map explicit entry
   "try__c_l_block_map_explicit_entry"
   (fn [receiver o]
     (cache-up receiver))

   "got__c_l_block_map_explicit_entry"
   (fn [receiver o]
     (cache-down receiver))

   "not__c_l_block_map_explicit_entry"
   (fn [receiver o]
     (cache-drop receiver))

   ;; Flow map empty key entry
   "try__c_ns_flow_map_empty_key_entry"
   (fn [receiver o]
     (cache-up receiver))

   "got__c_ns_flow_map_empty_key_entry"
   (fn [receiver o]
     (cache-down receiver))

   "not__c_ns_flow_map_empty_key_entry"
   (fn [receiver o]
     (cache-drop receiver))

   ;; Plain scalar
   "got__ns_plain"
   (fn [receiver o]
     (let [text (-> (:text o)
                    (str/replace #"(?:[ \t]*\r?\n[ \t]*)" "\n")
                    (str/replace #"(\n)(\n*)"
                                 (fn [[_ n1 n2]]
                                   (if (pos? (count n2)) n2 " "))))]
       (add-event receiver (scalar-event "plain" text))))

   ;; Single-quoted scalar
   "got__c_single_quoted"
   (fn [receiver o]
     (let [text (-> (:text o)
                    (subs 1 (dec (count (:text o))))  ;; strip quotes
                    (str/replace #"(?:[ \t]*\r?\n[ \t]*)" "\n")
                    (str/replace #"(\n)(\n*)"
                                 (fn [[_ n1 n2]]
                                   (if (pos? (count n2)) n2 " ")))
                    (str/replace "''" "'"))]
       (add-event receiver (scalar-event "single" text))))

   ;; Double-quoted scalar
   "got__c_double_quoted"
   (fn [receiver o]
     (let [inner (subs (:text o) 1 (dec (count (:text o))))
           text (unescape-double-quoted inner)]
       (add-event receiver (scalar-event "double" text))))

   ;; Literal block scalar
   "got__l_empty"
   (fn [receiver o]
     (when @(:in-scalar receiver)
       (add-event receiver (cache-text ""))))

   "got__l_nb_literal_text__all__rep2"
   (fn [receiver o]
     (add-event receiver (cache-text (:text o))))

   "try__c_l_literal"
   (fn [receiver o]
     (reset! (:in-scalar receiver) true)
     (cache-up receiver))

   "got__c_l_literal"
   (fn [receiver o]
     (reset! (:in-scalar receiver) false)
     (let [lines (cache-drop receiver)
           lines (if (and (seq lines) (= "" (:text (last lines))))
                   (butlast lines)
                   lines)
           lines (map #(str (:text %) "\n") lines)
           text (apply str lines)
           p (:parser receiver)
           t (:t (parser/state-curr p))
           text (cond
                  (= t "clip") (str/replace text #"\n+$" "\n")
                  (= t "strip") (str/replace text #"\n+$" "")
                  (not (re-find #"\S" text)) (str/replace text #"\n(\n+)$" "$1")
                  :else text)]
       (add-event receiver (scalar-event "literal" text))))

   "not__c_l_literal"
   (fn [receiver o]
     (reset! (:in-scalar receiver) false)
     (cache-drop receiver))

   ;; Folded block scalar
   "got__ns_char"
   (fn [receiver o]
     (when @(:in-scalar receiver)
       (reset! (:first receiver) (:text o))))

   "got__s_white"
   (fn [receiver o]
     (when @(:in-scalar receiver)
       (reset! (:first receiver) (:text o))))

   "got__s_nb_folded_text__all__rep"
   (fn [receiver o]
     (add-event receiver (cache-text (str @(:first receiver) (:text o)))))

   "got__s_nb_spaced_text__all__rep"
   (fn [receiver o]
     (add-event receiver (cache-text (str @(:first receiver) (:text o)))))

   "try__c_l_folded"
   (fn [receiver o]
     (reset! (:in-scalar receiver) true)
     (reset! (:first receiver) "")
     (cache-up receiver))

   "got__c_l_folded"
   (fn [receiver o]
     (reset! (:in-scalar receiver) false)
     (let [lines (map :text (cache-drop receiver))
           text (str/join "\n" lines)
           text #?(:clj (-> text
                            ;; Use re-pattern strings (not literals) to avoid RE2
                            ;; compile errors when Gloat reads this file
                            (str/replace (re-pattern "(?m)^(\\S.*)\\n(?=\\S)") "$1 ")
                            (str/replace (re-pattern "(?m)^(\\S.*)\\n(?=\\n+)") "$1")
                            (str/replace (re-pattern "(?m)^([ \\t]+\\S.*)\\n(?=\\n+\\S)") "$1"))
                   :glj (-> text
                            ;; RE2 lacks lookaheads; capture and reinsert next char
                            (str/replace #"(?m)^(\S.*)\n(\S)" "$1 $2")
                            (str/replace #"(?m)^(\S.*)\n(\n+)" "$1$2")
                            (str/replace #"(?m)^([ \t]+\S.*)\n(\n+)(\S)" "$1$2$3")))
           text (str text "\n")
           p (:parser receiver)
           t (:t (parser/state-curr p))
           text (cond
                  (= t "clip") (let [t (str/replace text #"\n+$" "\n")]
                                 (if (= t "\n") "" t))
                  (= t "strip") (str/replace text #"\n+$" "")
                  :else text)]
       (add-event receiver (scalar-event "folded" text))))

   "not__c_l_folded"
   (fn [receiver o]
     (reset! (:in-scalar receiver) false)
     (cache-drop receiver))

   ;; Empty scalar
   "got__e_scalar"
   (fn [receiver o]
     (add-event receiver (scalar-event "plain" "")))

   ;; Block collection properties cleanup
   "not__s_l_block_collection__all__rep__all__any__all"
   (fn [receiver o]
     (reset! (:tag receiver) nil)
     (reset! (:anchor receiver) nil))

   ;; Anchor property
   "got__c_ns_anchor_property"
   (fn [receiver o]
     (reset! (:anchor receiver) (subs (:text o) 1)))

   ;; Tag property
   "got__c_ns_tag_property"
   (fn [receiver o]
     (let [tag (:text o)
           tag-map @(:tag-map receiver)
           resolved-tag
           (cond
             ;; Verbatim tag: !<tag>
             (re-matches #"^!<(.*)>$" tag)
             (second (re-matches #"^!<(.*)>$" tag))

             ;; Secondary tag handle: !!suffix
             (re-matches #"^!!(.*)" tag)
             (let [[_ suffix] (re-matches #"^!!(.*)" tag)
                   prefix (get tag-map "!!")]
               (if prefix
                 (str prefix (subs tag 2))
                 (str "tag:yaml.org,2002:" suffix)))

             ;; Named tag handle: !name!suffix (use re-find, not re-matches)
             (re-find #"^(!.*?!)" tag)
             (let [[full-match handle] (re-find #"^(!.*?!)" tag)
                   prefix (get tag-map handle)]
               (if prefix
                 (str prefix (subs tag (count full-match)))
                 (die (str "No %TAG entry for '" handle "'"))))

             ;; Primary tag handle: !suffix
             (get tag-map "!")
             (str (get tag-map "!") (subs tag 1))

             :else tag)
           ;; URL-decode percent escapes
           resolved-tag (str/replace resolved-tag #"%([0-9a-fA-F]{2})"
                                     (fn [[_ hex]]
                                       (hex->char hex)))]
       (reset! (:tag receiver) resolved-tag)))

   ;; Alias node
   "got__c_ns_alias_node"
   (fn [receiver o]
     (add-event receiver (alias-event (subs (:text o) 1))))})

;; Create a receiver with callbacks attached
(defn make-receiver-with-callbacks []
  (assoc (make-receiver) :callbacks receiver-callbacks))
