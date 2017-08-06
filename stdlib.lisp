(def (+ *args)
  (args | reduce +))

(def (- *args)
  (args | reduce -))

(def (/ *args)
  (args | reduce /))

(def (* *args)
  (args | reduce *))

(def (% *args)
  (args | reduce %))

(def (< *args)
  (args | reduce <))

(def (> *args)
  (args | reduce >))
