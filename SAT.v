Require Import List Ensembles String Setoid RelationClasses Morphisms Morphisms_Prop Program Equivalence.
Require Import JMeq ProofIrrelevance.

Set Implicit Arguments.
Generalizable All Variables.

Reserved Notation "x >>= y" (at level 42, right associativity).
Reserved Notation "x <- y ; z" (at level 42, right associativity).
Reserved Notation "x ;; z" (at level 42, right associativity).
Reserved Notation "'return' x" (at level 40, no associativity).

Delimit Scope comp_scope with comp.

Ltac apply_in_hyp lem :=
  match goal with
    | [ H : _ |- _ ] => apply lem in H
  end.

Ltac apply_in_hyp_no_match lem :=
  match goal with
    | [ H : _ |- _ ] => apply lem in H;
      match type of H with
        | appcontext[match _ with _ => _ end] => fail 1
        | _ => idtac
      end
  end.

Ltac destruct_ex :=
  repeat match goal with
           | [ H : ex _ |- _ ] => destruct H; intuition
         end.

Hint Extern 0 => apply reflexivity : typeclass_instances.

Ltac set_evars :=
  repeat match goal with
           | [ |- appcontext[?E] ] => is_evar E; let H := fresh in set (H := E)
         end.

Instance pointwise_refl A B (eqB : relation B) `{Reflexive _ eqB} : Reflexive (pointwise_relation A eqB).
Proof.
  compute in *; auto.
Defined.

Instance pointwise_sym A B (eqB : relation B) `{Symmetric _ eqB} : Symmetric (pointwise_relation A eqB).
Proof.
  compute in *; auto.
Defined.

Instance pointwise_transitive A B (eqB : relation B) `{Transitive _ eqB} : Transitive (pointwise_relation A eqB).
Proof.
  compute in *; eauto.
Defined.

Section formulas.
  Inductive formula (vars : Type) :=
  | Atomic : vars -> formula vars
  | And : formula vars -> formula vars -> formula vars
  | Not : formula vars -> formula vars
  | TrueF : formula vars.

  Fixpoint get_vars vars (f : formula vars) : Ensemble vars :=
    match f with
      | Atomic x => Singleton _ x
      | And x y => Union _ (get_vars x) (get_vars y)
      | Not x => get_vars x
      | TrueF => Empty_set _
    end.

  Fixpoint denote_formula vars (bool_map : vars -> bool) (f : formula vars)
  : bool
    := match f with
         | Atomic x => bool_map x
         | And x y => andb (denote_formula bool_map x) (denote_formula bool_map y)
         | Not x => negb (denote_formula bool_map x)
         | TrueF => true
       end.

  Definition is_satisfiable vars (f : formula vars) : Prop
    := exists bool_map, denote_formula bool_map f = true.

  Fixpoint subst_vars vars (bool_map : vars -> vars + bool) (f : formula vars)
  : formula vars
    := match f with
         | TrueF => TrueF _
         | Atomic x => match bool_map x with
                         | inl x' => Atomic x'
                         | inr b => if b then TrueF _ else Not (TrueF _)
                       end
         | And x y => And (subst_vars bool_map x) (subst_vars bool_map y)
         | Not x => Not (subst_vars bool_map x)
       end.
End formulas.

Section funcs.
  Variable funcs : string -> Type * Type.
  Inductive Comp : Type -> Type :=
  | Return : forall A, A -> Comp A
  | Bind : forall A B, Comp A -> (A -> Comp B) -> Comp B
  | Call : forall x, fst (funcs x) -> Comp (snd (funcs x))
  | Pick : forall A, Ensemble A -> Comp A.

  Bind Scope comp_scope with Comp.
  Global Arguments Bind A%type B%type _%comp _.

  Notation "x >>= y" := (Bind x y) : comp_scope.
  Notation "x <- y ; z" := (Bind y (fun x => z)) : comp_scope.
  Notation "x ;; z" := (Bind x (fun _ => z)) : comp_scope.
  Notation "f [[ x ]]" := (@Call f x) (at level 35) : comp_scope.
  Notation "{ x  |  P }" := (@Pick _ (fun x => P)) : comp_scope.
  Notation "{ x : A  |  P }" := (@Pick A (fun x => P)) : comp_scope.

  Definition Or : Comp bool -> Comp bool -> Comp bool
    := fun c1 c2 =>
         (b1 <- c1;
          if b1
          then Return true
          else c2)%comp.

  Variable denote_funcs : forall name, fst (funcs name) -> Comp (snd (funcs name)).

  Inductive computes_to
  : forall A : Type, Comp A -> A -> Prop :=
  | ReturnComputes : forall A v, @computes_to A (Return v) v
  | BindComputes : forall A B comp_a f comp_a_value comp_b_value,
                     @computes_to A comp_a comp_a_value
                     -> @computes_to B (f comp_a_value) comp_b_value
                     -> @computes_to B (Bind comp_a f) comp_b_value
  | PickComputes : forall A (P : Ensemble A) v, P v -> @computes_to A (Pick P) v
  | CallComputes : forall name (input : fst (funcs name)) (output_v : snd (funcs name)),
                     @computes_to _ (denote_funcs name input) output_v
                     -> @computes_to _ (Call name input) output_v.

  Theorem computes_to_inv A (c : Comp A) v
    : computes_to c v -> match c with
                           | Return _ x => fun v => v = x
                           | Bind _ _ x f => fun v => exists comp_a_value,
                             computes_to x comp_a_value
                             /\ computes_to (f comp_a_value) v
                           | Call name input => computes_to (denote_funcs name input)
                           | Pick _ P => P
                         end v.
  Proof.
    destruct 1; eauto.
  Qed.

  (** The old program might be non-deterministic, and the new program
      less so.  This means we want to say that if [new] can compute to
      [v], then [old] should be able to compute to [v], too. *)
  Definition refine {A} (old new : Comp A) := forall v, computes_to new v -> computes_to old v.

  Global Instance refine_PreOrder A : PreOrder (@refine A).
  Proof.
    split; compute in *; eauto.
  Qed.

  Section monad.
    Local Ltac t :=
      split;
      intro;
      repeat match goal with
               | [ H : _ |- _ ]
                 => inversion H; clear H; subst; [];
                    repeat match goal with
                             | [ H : _ |- _ ] => apply inj_pair2 in H; subst
                           end
             end;
      repeat first [ eassumption
                   | solve [ constructor ]
                   | eapply BindComputes; (eassumption || (try eassumption; [])) ].

    Lemma bind_bind X Y Z (f : X -> Comp Y) (g : Y -> Comp Z) x v
    : computes_to (Bind (Bind x f) g) v
      <-> computes_to (Bind x (fun u => Bind (f u) g)) v.
    Proof.
      t.
    Qed.

    Lemma bind_unit X Y (f : X -> Comp Y) x v
    : computes_to (Bind (Return x) f) v
      <-> computes_to (f x) v.
    Proof.
      t.
    Qed.

    Lemma unit_bind X (x : Comp X) v
    : computes_to (Bind x (@Return X)) v
      <-> computes_to x v.
    Proof.
      t.
    Qed.
  End monad.
End funcs.

Hint Constructors computes_to.

Notation "x >>= y" := (Bind x y) : comp_scope.
Notation "x <- y ; z" := (Bind y (fun x => z)) : comp_scope.
Notation "x ;; z" := (Bind x (fun _ => z)) : comp_scope.
Notation "'call' f 'from' funcs [[ x ]]" := (@Call funcs f x) (at level 35) : comp_scope.
Notation "{ x  |  P }" := (@Pick _ _ (fun x => P)) : comp_scope.
Notation "{ x : A  |  P }" := (@Pick _ A (fun x => P)) : comp_scope.
Notation ret := (Return _).

Add Parametric Relation funcs denote_funcs A : (Comp funcs A) (@refine funcs denote_funcs A)
  reflexivity proved by reflexivity
  transitivity proved by transitivity
    as refine_rel.

Add Parametric Morphism funcs denote_funcs A B : (@Bind funcs A B)
  with signature (@refine funcs denote_funcs A) ==> (pointwise_relation _ (@refine funcs denote_funcs B)) ==> (@refine funcs denote_funcs B)
    as refine_bind.
Proof.
  intros.
  unfold pointwise_relation, refine in *.
  intros.
  repeat (repeat apply_in_hyp_no_match computes_to_inv;
    destruct_ex).
  eauto.
Qed.

(**Add Parametric Morphism A (R : relation A) `{Transitive A R} : R
  with signature R --> R ++> impl
    as trans_rel_mor.
Proof.
  repeat intro; unfold Transitive in *.
  intros; intuition eauto.
Qed.

Add Parametric Morphism A (R : relation A) `{Transitive A R} : R
  with signature R ++> R --> flip impl
    as trans_rel_mor_flip.
Proof.
  repeat intro; unfold Transitive in *.
  intros; intuition eauto.
Qed.*)

Section op_funcs.
  Variable op : nat -> nat -> Prop.
  Variable on_empty : nat -> Prop.
  Definition is_op (l : list nat) (v : nat)
    := Forall (fun n => op v n) l /\ (List.In v l \/ (l = nil /\ on_empty v)).

  Variable funcs : string -> Type * Type.
  Variable denote_funcs : forall name, fst (funcs name) -> Comp funcs (snd (funcs name)).

  Definition is_op0 (l : list nat) : Comp funcs nat :=
    { x : nat
      | is_op l x }%comp.

  Variable concrete_op : nat -> nat -> nat.
  Variable concrete_on_empty : nat.
  Hypothesis on_empty_concrete_on_empty : on_empty concrete_on_empty.
  Hypothesis concrete_op_returns_arg : forall n m,
    concrete_op n m = n \/ concrete_op n m = m.
  Hypothesis concrete_op_preserves_op1 : forall n m,
    op (concrete_op n m) m.
  Hypothesis concrete_op_preserves_op2 : forall n m,
    op (concrete_op n m) n.
  Hypothesis op_refl : Reflexive op.
  Hypothesis op_trans : Transitive op.

  Definition is_op1 (l : list nat) : Comp funcs (nat : Type) :=
    (ret (match l with
            | nil => concrete_on_empty
            | x::xs => fold_right concrete_op x xs
          end))%comp.

  Lemma fold_right_concrete_op_preserves_op l
    : forall acc,
      op (fold_right concrete_op acc l) acc.
  Proof.
    induction l; simpl; eauto.
  Qed.

  Hint Resolve fold_right_concrete_op_preserves_op.

  Local Hint Constructors or.

  Lemma fold_right_concrete_op_returns_in l
    : forall acc,
      acc = fold_right concrete_op acc l
      \/ List.In (fold_right concrete_op acc l) l.
  Proof.
    induction l; simpl; eauto.
    intro acc.
    destruct (IHl acc) as [ IH1' | IH1' ];
      try rewrite <- IH1';
      edestruct concrete_op_returns_arg as [H|H];
      erewrite H;
      eauto.
  Qed.

  Hint Resolve fold_right_concrete_op_returns_in.

  Lemma op_works l
  : Forall (fun n => match l with
                       | [] => True
                       | v::l => op (fold_right concrete_op v l) n
                     end)
           l.
  Proof.
    induction l; trivial.
    constructor; [ apply fold_right_concrete_op_preserves_op | ].
    destruct l; simpl in *; trivial.
    inversion_clear IHl.
    constructor;
      eauto.
    eapply Forall_impl; [ | eassumption ]; instantiate; simpl.
    intros.
    etransitivity; [ | eassumption ].
    admit.
  Qed.

  Theorem is_op_0_1
    : pointwise_relation _ (refine denote_funcs) is_op0 is_op1.
  Proof.
    intros l v old_hyp.
    unfold is_op1, is_op0 in *.
    apply computes_to_inv in old_hyp.
    subst.
    constructor.
    destruct l; simpl.
    - hnf; simpl; intuition.
    - split; [ | left; apply fold_right_concrete_op_returns_in ].
      apply (op_works (_::_)).
  Qed.
End op_funcs.

Create HintDb op discriminated.

Hint Unfold is_op0 is_op1 : op.

Section min_max_funcs.
  Definition is_minimum := is_op le (eq 0).
  Definition is_maximum := is_op ge (eq 0).
  Definition is_min_max l (min_max : nat * nat) :=
    is_minimum l (fst min_max) /\ is_maximum l (snd min_max).

  Variable funcs : string -> Type * Type.
  Variable denote_funcs : forall name, fst (funcs name) -> Comp funcs (snd (funcs name)).

  Definition is_min_max0 (l : list nat) : Comp funcs (nat * nat) :=
    { x : _
      | is_min_max l x }%comp.

  Definition is_minimum0 := (is_op0 le (eq 0) funcs : list nat -> Comp funcs nat).
  Definition is_maximum0 := (is_op0 ge (eq 0) funcs : list nat -> Comp funcs nat).

  Definition is_minimum1 := (is_op1 funcs min 0 : list nat -> Comp funcs nat).
  Definition is_maximum1 := (is_op1 funcs max 0 : list nat -> Comp funcs nat).

  Hint Unfold is_minimum is_maximum is_min_max is_min_max0 is_minimum0 is_maximum0 is_minimum1 is_maximum1 : op.

  Theorem refine_is_minimum : pointwise_relation _ (refine denote_funcs) is_minimum0 is_minimum1.
  Proof.
    apply is_op_0_1.
  Qed.

  Theorem refine_is_maximum : pointwise_relation _ (refine denote_funcs) is_maximum0 is_maximum1.
  Proof.
    apply is_op_0_1.
  Qed.

  (*Theorem refine_is_minimum' : pointwise_relation _ (refine denote_funcs)
    (fun l => { x : nat | is_op le (eq 0) l x }%comp)
    (fun l => (ret (match l with
                      | nil => 0
                      | x::xs => fold_left min xs x
                    end))%comp).
  Proof.
    exact refine_is_minimum.
  Qed.

  Theorem refine_is_maximum' : pointwise_relation _ (refine denote_funcs)
    (fun l => { x : nat | is_op ge (eq 0) l x }%comp)
    (fun l => (ret (match l with
                      | nil => 0
                      | x::xs => fold_left max xs x
                    end))%comp).
  Proof.
    exact refine_is_maximum.
  Qed.*)

  Theorem refine_is_minimum' l : refine denote_funcs
    { x : nat | is_op le (eq 0) l x }%comp
    (ret (match l with
            | nil => 0
            | x::xs => fold_left min xs x
          end))%comp.
  Proof.
    apply refine_is_minimum.
  Qed.

  Theorem refine_is_maximum' l : refine denote_funcs
    { x : nat | is_op ge (eq 0) l x }%comp
    (ret (match l with
            | nil => 0
            | x::xs => fold_left max xs x
          end))%comp.
  Proof.
    apply refine_is_maximum.
  Qed.

  Lemma refine_pick_pair A B (PA : A -> Prop) (PB : B -> Prop)
    : refine denote_funcs
      { x : A * B | PA (fst x) /\ PB (snd x) }%comp
      (a <- { a : A | PA a };
        b <- { b : B | PB b };
        ret (a, b))%comp.
  Proof.
    intros (a, b) H.
    repeat match goal with
             | _ => constructor; tauto
             | _ => progress destruct_ex
             | [ H : (_, _) = (_, _) |- _ ] => inversion_clear H
             | [ H : _ |- _ ] => apply computes_to_inv in H
           end.
  Qed.

  Definition is_min_max1 : { f : list nat -> Comp funcs (nat * nat)
    | forall l, refine denote_funcs (is_min_max0 l) (f l) }.
  Proof.
    eexists.
    intros.
    repeat autounfold with op.
    set_evars.
    rewrite refine_pick_pair.
    rewrite refine_is_minimum'.
    setoid_rewrite refine_is_maximum'.
    exact (reflexivity _).
  Defined.
End min_max_funcs.


Section sat_funcs.
  Variable var : Type.
  Variable dec_eq : forall x y : var, {x = y} + {x <> y}.

  Definition funcs : string -> Type * Type
    := (fun s =>
      if string_dec s "sat"
      then (formula var, bool : Type)
      else (Datatypes.Empty_set : Type, unit : Type)).

  Definition sat (f : formula var)
  : Comp funcs bool :=
    (x0 <- { x0 : option var
           | (x0 = None /\ get_vars f = Empty_set _)
             \/ (exists x', x0 = Some x' /\ In _ (get_vars f) x') };
     match x0 with
       | None => ret (denote_formula (fun _ => false (* do we want to use a [Prop] here? *)) f)
       | Some x0 =>
         let bool_map_t v := if dec_eq x0 v then inr true else inl v in
         let bool_map_f v := if dec_eq x0 v then inr false else inl v in
         let formula_t := subst_vars bool_map_t f in
         let formula_f := subst_vars bool_map_f f in
         Or (call "sat" from funcs [[ formula_t ]]) (call "sat" from funcs [[ formula_f ]])
     end)%comp.
End sat_funcs.
