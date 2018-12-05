open Format
open Syntax
open Support.Error
open Support.Pervasive

(* ------------------------   EVALUATION  ------------------------ *)

let rec isval ctx t = match t with
    TmAbs(_,_,_,_) -> true
  | TmTAbs(_,_,_,_) -> true
  | _ -> false

exception NoRuleApplies

let rec eval1 ctx t = match t with
    TmApp(fi,TmAbs(_,x,tyT11,t12),v2) when isval ctx v2 ->
      termSubstTop v2 t12
  | TmApp(fi,v1,t2) when isval ctx v1 ->
      let t2' = eval1 ctx t2 in
      TmApp(fi, v1, t2')
  | TmApp(fi,t1,t2) ->
      let t1' = eval1 ctx t1 in
      TmApp(fi, t1', t2)
  | TmTApp(fi,TmTAbs(_,x,_,t11),tyT2) ->
      tytermSubstTop tyT2 t11
  | TmTApp(fi,t1,tyT2) ->
      let t1' = eval1 ctx t1 in
      TmTApp(fi, t1', tyT2)
  | _ -> 
      raise NoRuleApplies

let rec eval ctx t =
  try let t' = eval1 ctx t
      in eval ctx t'
  with NoRuleApplies -> t

(* ------------------------   KINDING  ------------------------ *)

let rec computety ctx tyT = match tyT with
    TyApp(TyAbs(_,_,tyT12),tyT2) -> typeSubstTop tyT2 tyT12
  | _ -> raise NoRuleApplies

let rec simplifyty ctx tyT =
  let tyT = 
    match tyT with
        TyApp(tyT1,tyT2) -> TyApp(simplifyty ctx tyT1,tyT2)
      | tyT -> tyT
  in 
  try
    let tyT' = computety ctx tyT in
    simplifyty ctx tyT' 
  with NoRuleApplies -> tyT

let rec tyeqv ctx tyS tyT =
  let tyS = simplifyty ctx tyS in
  let tyT = simplifyty ctx tyT in
  match (tyS,tyT) with
    (TyVar(i,_),TyVar(j,_)) -> i=j
  | (TyAll(tyX1,knK1,tyS2),TyAll(_,knK2,tyT2)) ->
       let ctx1 = addname ctx tyX1 in
       (=) knK1 knK2 && tyeqv ctx1 tyS2 tyT2
  | (TyAbs(tyX1,knKS1,tyS2),TyAbs(_,knKT1,tyT2)) ->
       ((=) knKS1 knKT1)
      &&
       (let ctx = addname ctx tyX1 in
        tyeqv ctx tyS2 tyT2)
  | (TyApp(tyS1,tyS2),TyApp(tyT1,tyT2)) ->
       (tyeqv ctx tyS1 tyT1) && (tyeqv ctx tyS2 tyT2)
  | (TyArr(tyS1,tyS2),TyArr(tyT1,tyT2)) ->
       (tyeqv ctx tyS1 tyT1) && (tyeqv ctx tyS2 tyT2)
  | _ -> false

let getkind fi ctx i =
  match getbinding fi ctx i with
      TyVarBind(knK) -> knK
    | _ -> error fi ("getkind: Wrong kind of binding for variable " 
                     ^ (index2name fi ctx i))

let rec kindof ctx tyT = match tyT with
    TyVar(i,_) ->
      let knK = getkind dummyinfo ctx i
      in knK
  | TyAll(tyX,knK1,tyT2) ->
      let ctx' = addbinding ctx tyX (TyVarBind knK1) in
      if kindof ctx' tyT2 <> KnStar then error dummyinfo "Kind * expected";
      KnStar
  | TyAbs(tyX,knK1,tyT2) ->
      let ctx' = addbinding ctx tyX (TyVarBind(knK1)) in
      let knK2 = kindof ctx' tyT2 in
      KnArr(knK1,knK2)
  | TyApp(tyT1,tyT2) ->
      let knK1 = kindof ctx tyT1 in
      let knK2 = kindof ctx tyT2 in
      (match knK1 with
          KnArr(knK11,knK12) ->
            if (=) knK2 knK11 then knK12
            else error dummyinfo "parameter kind mismatch"
        | _ -> error dummyinfo "arrow kind expected")
  | TyArr(tyT1,tyT2) ->
      if kindof ctx tyT1 <> KnStar then error dummyinfo "star kind expected";
      if kindof ctx tyT2 <> KnStar then error dummyinfo "star kind expected";
      KnStar
  | _ -> KnStar

let checkkindstar fi ctx tyT = 
  let k = kindof ctx tyT in
  if k = KnStar then ()
  else error fi "Kind * expected"

(* ------------------------   TYPING  ------------------------ *)

let rec typeof ctx t =
  match t with
    TmVar(fi,i,_) -> getTypeFromContext fi ctx i
  | TmAbs(fi,x,tyT1,t2) ->
      checkkindstar fi ctx tyT1;
      let ctx' = addbinding ctx x (VarBind(tyT1)) in
      let tyT2 = typeof ctx' t2 in
      TyArr(tyT1, typeShift (-1) tyT2)
  | TmApp(fi,t1,t2) ->
      let tyT1 = typeof ctx t1 in
      let tyT2 = typeof ctx t2 in
      (match simplifyty ctx tyT1 with
          TyArr(tyT11,tyT12) ->
            if tyeqv ctx tyT2 tyT11 then tyT12
            else error fi "parameter type mismatch"
        | _ -> error fi "arrow type expected")
  | TmTAbs(fi,tyX,knK1,t2) ->
      let ctx = addbinding ctx tyX (TyVarBind(knK1)) in
      let tyT2 = typeof ctx t2 in
      TyAll(tyX,knK1,tyT2)
  | TmTApp(fi,t1,tyT2) ->
      let knKT2 = kindof ctx tyT2 in
      let tyT1 = typeof ctx t1 in
      (match simplifyty ctx tyT1 with
           TyAll(_,knK11,tyT12) ->
             if knK11 <> knKT2 then
               error fi "Type argument has wrong kind";
             typeSubstTop tyT2 tyT12
         | _ -> error fi "universal type expected")
