(* α. (* nested comment with a dot. *) *)
Check Nat.add.
Lemma both (P : Prop) : P -> P /\ P.
Proof.
  intros H.
  split.
  - exact H.
  (* α *) - exact H.
Qed.
