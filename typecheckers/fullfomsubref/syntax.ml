open Format
open Support.Error
open Support.Pervasive

(* ---------------------------------------------------------------------- *)
(* Datatypes *)

type kind = 
    KnStar
  | KnArr of kind * kind

type ty =
    TyId of string
  | TyVar of int * int
  | TyBool
  | TyTop
  | TyBot
  | TyArr of ty * ty
  | TyRecord of (string * ty) list
  | TyVariant of (string * ty) list
  | TyRef of ty
  | TyFloat
  | TyString
  | TyUnit
  | TyAll of string * ty * ty
  | TyNat
  | TySome of string * ty * ty
  | TySource of ty
  | TySink of ty
  | TyAbs of string * kind * ty
  | TyApp of ty * ty


type term =
    TmVar of info * int * int
  | TmAbs of info * string * ty * term
  | TmApp of info * term * term
  | TmTrue of info
  | TmFalse of info
  | TmIf of info * term * term * term
  | TmRecord of info * (string * term) list
  | TmProj of info * term * string
  | TmLet of info * string * term * term
  | TmFloat of info * float
  | TmTimesfloat of info * term * term
  | TmAscribe of info * term * ty
  | TmString of info * string
  | TmUnit of info
  | TmFix of info * term
  | TmCase of info * term * (string * (string * term)) list
  | TmTag of info * string * term * ty
  | TmLoc of info * int
  | TmRef of info * term
  | TmDeref of info * term 
  | TmAssign of info * term * term
  | TmError of info
  | TmTry of info * term * term
  | TmTAbs of info * string * ty * term
  | TmTApp of info * term * ty
  | TmZero of info
  | TmSucc of info * term
  | TmPred of info * term
  | TmIsZero of info * term
  | TmInert of info * ty
  | TmPack of info * ty * term * ty
  | TmUnpack of info * string * string * term * term

type binding =
    NameBind 
  | TyVarBind of ty
  | VarBind of ty
  | TyAbbBind of ty * (kind option)
  | TmAbbBind of term * (ty option)

type context = (string * binding) list

type command =
    Import of string
  | Eval of info * term
  | Bind of info * string * binding
  | SomeBind of info * string * string * term

(* ---------------------------------------------------------------------- *)
(* Context management *)

let emptycontext = []

let ctxlength ctx = List.length ctx

let addbinding ctx x bind = (x,bind)::ctx

let addname ctx x = addbinding ctx x NameBind

let rec isnamebound ctx x =
  match ctx with
      [] -> false
    | (y,_)::rest ->
        if y=x then true
        else isnamebound rest x

let rec pickfreshname ctx x =
  if isnamebound ctx x then pickfreshname ctx (x^"'")
  else ((x,NameBind)::ctx), x

let index2name fi ctx x =
  try
    let (xn,_) = List.nth ctx x in
    xn
  with Failure _ ->
    let msg =
      Printf.sprintf "Variable lookup failure: offset: %d, ctx size: %d" in
    error fi (msg x (List.length ctx))

let rec name2index fi ctx x =
  match ctx with
      [] -> error fi ("Identifier " ^ x ^ " is unbound")
    | (y,_)::rest ->
        if y=x then 0
        else 1 + (name2index fi rest x)

(* ---------------------------------------------------------------------- *)
(* Shifting *)

let tymap onvar c tyT = 
  let rec walk c tyT = match tyT with
    TyId(b) as tyT -> tyT
  | TyVar(x,n) -> onvar c x n
  | TyArr(tyT1,tyT2) -> TyArr(walk c tyT1,walk c tyT2)
  | TyBool -> TyBool
  | TyTop -> TyTop
  | TyBot -> TyBot
  | TyRecord(fieldtys) -> TyRecord(List.map (fun (li,tyTi) -> (li, walk c tyTi)) fieldtys)
  | TyVariant(fieldtys) -> TyVariant(List.map (fun (li,tyTi) -> (li, walk c tyTi)) fieldtys)
  | TyFloat -> TyFloat
  | TyString -> TyString
  | TyUnit -> TyUnit
  | TyAll(tyX,tyT1,tyT2) -> TyAll(tyX,walk c tyT1,walk (c+1) tyT2)
  | TyNat -> TyNat
  | TySome(tyX,tyT1,tyT2) -> TySome(tyX,walk c tyT1,walk (c+1) tyT2)
  | TyAbs(tyX,knK1,tyT2) -> TyAbs(tyX,knK1,walk (c+1) tyT2)
  | TyApp(tyT1,tyT2) -> TyApp(walk c tyT1,walk c tyT2)
  | TyRef(tyT1) -> TyRef(walk c tyT1)
  | TySource(tyT1) -> TySource(walk c tyT1)
  | TySink(tyT1) -> TySink(walk c tyT1)
  in walk c tyT

let tmmap onvar ontype c t = 
  let rec walk c t = match t with
    TmVar(fi,x,n) -> onvar fi c x n
  | TmAbs(fi,x,tyT1,t2) -> TmAbs(fi,x,ontype c tyT1,walk (c+1) t2)
  | TmApp(fi,t1,t2) -> TmApp(fi,walk c t1,walk c t2)
  | TmTrue(fi) as t -> t
  | TmFalse(fi) as t -> t
  | TmIf(fi,t1,t2,t3) -> TmIf(fi,walk c t1,walk c t2,walk c t3)
  | TmProj(fi,t1,l) -> TmProj(fi,walk c t1,l)
  | TmRecord(fi,fields) -> TmRecord(fi,List.map (fun (li,ti) ->
                                               (li,walk c ti))
                                    fields)
  | TmLet(fi,x,t1,t2) -> TmLet(fi,x,walk c t1,walk (c+1) t2)
  | TmFloat _ as t -> t
  | TmTimesfloat(fi,t1,t2) -> TmTimesfloat(fi, walk c t1, walk c t2)
  | TmAscribe(fi,t1,tyT1) -> TmAscribe(fi,walk c t1,ontype c tyT1)
  | TmInert(fi,tyT) -> TmInert(fi,ontype c tyT)
  | TmFix(fi,t1) -> TmFix(fi,walk c t1)
  | TmTag(fi,l,t1,tyT) -> TmTag(fi, l, walk c t1, ontype c tyT)
  | TmCase(fi,t,cases) ->
      TmCase(fi, walk c t,
             List.map (fun (li,(xi,ti)) -> (li, (xi,walk (c+1) ti)))
               cases)
  | TmString _ as t -> t
  | TmUnit(fi) as t -> t
  | TmLoc(fi,l) as t -> t
  | TmRef(fi,t1) -> TmRef(fi,walk c t1)
  | TmDeref(fi,t1) -> TmDeref(fi,walk c t1)
  | TmAssign(fi,t1,t2) -> TmAssign(fi,walk c t1,walk c t2)
  | TmError(_) as t -> t
  | TmTry(fi,t1,t2) -> TmTry(fi,walk c t1,walk c t2)
  | TmTAbs(fi,tyX,tyT1,t2) ->
      TmTAbs(fi,tyX,ontype c tyT1,walk (c+1) t2)
  | TmTApp(fi,t1,tyT2) -> TmTApp(fi,walk c t1,ontype c tyT2)
  | TmZero(fi)      -> TmZero(fi)
  | TmSucc(fi,t1)   -> TmSucc(fi, walk c t1)
  | TmPred(fi,t1)   -> TmPred(fi, walk c t1)
  | TmIsZero(fi,t1) -> TmIsZero(fi, walk c t1)
  | TmPack(fi,tyT1,t2,tyT3) ->
      TmPack(fi,ontype c tyT1,walk c t2,ontype c tyT3)
  | TmUnpack(fi,tyX,x,t1,t2) ->
      TmUnpack(fi,tyX,x,walk c t1,walk (c+2) t2)
  in walk c t

let typeShiftAbove d c tyT =
  tymap
    (fun c x n -> if x>=c then TyVar(x+d,n+d) else TyVar(x,n+d))
    c tyT

let termShiftAbove d c t =
  tmmap
    (fun fi c x n -> if x>=c then TmVar(fi,x+d,n+d) 
                     else TmVar(fi,x,n+d))
    (typeShiftAbove d)
    c t

let termShift d t = termShiftAbove d 0 t

let typeShift d tyT = typeShiftAbove d 0 tyT

let bindingshift d bind =
  match bind with
    NameBind -> NameBind
  | TyVarBind(tyS) -> TyVarBind(typeShift d tyS)
  | VarBind(tyT) -> VarBind(typeShift d tyT)
  | TyAbbBind(tyT,opt) -> TyAbbBind(typeShift d tyT,opt)
  | TmAbbBind(t,tyT_opt) ->
     let tyT_opt' = match tyT_opt with
                      None->None
                    | Some(tyT) -> Some(typeShift d tyT) in
     TmAbbBind(termShift d t, tyT_opt')

(* ---------------------------------------------------------------------- *)
(* Substitution *)

let termSubst j s t =
  tmmap
    (fun fi j x n -> if x=j then termShift j s else TmVar(fi,x,n))
    (fun j tyT -> tyT)
    j t

let termSubstTop s t = 
  termShift (-1) (termSubst 0 (termShift 1 s) t)

let typeSubst tyS j tyT =
  tymap
    (fun j x n -> if x=j then (typeShift j tyS) else (TyVar(x,n)))
    j tyT

let typeSubstTop tyS tyT = 
  typeShift (-1) (typeSubst (typeShift 1 tyS) 0 tyT)

let rec tytermSubst tyS j t =
  tmmap (fun fi c x n -> TmVar(fi,x,n))
        (fun j tyT -> typeSubst tyS j tyT) j t

let tytermSubstTop tyS t = 
  termShift (-1) (tytermSubst (typeShift 1 tyS) 0 t)

(* ---------------------------------------------------------------------- *)
(* Context management (continued) *)

let rec getbinding fi ctx i =
  try
    let (_,bind) = List.nth ctx i in
    bindingshift (i+1) bind 
  with Failure _ ->
    let msg =
      Printf.sprintf "Variable lookup failure: offset: %d, ctx size: %d" in
    error fi (msg i (List.length ctx))
 let getTypeFromContext fi ctx i =
   match getbinding fi ctx i with
         VarBind(tyT) -> tyT
     | TmAbbBind(_,Some(tyT)) -> tyT
     | TmAbbBind(_,None) -> error fi ("No type recorded for variable "
                                        ^ (index2name fi ctx i))
     | _ -> error fi 
       ("getTypeFromContext: Wrong kind of binding for variable " 
         ^ (index2name fi ctx i)) 

let rec maketop k = match k with
    KnStar -> TyTop
  | KnArr(knK1,knK2) -> TyAbs("_",knK1,maketop knK2)
(* ---------------------------------------------------------------------- *)
(* Extracting file info *)

let tmInfo t = match t with
    TmVar(fi,_,_) -> fi
  | TmAbs(fi,_,_,_) -> fi
  | TmApp(fi, _, _) -> fi
  | TmTrue(fi) -> fi
  | TmFalse(fi) -> fi
  | TmIf(fi,_,_,_) -> fi
  | TmProj(fi,_,_) -> fi
  | TmRecord(fi,_) -> fi
  | TmLet(fi,_,_,_) -> fi
  | TmFloat(fi,_) -> fi
  | TmTimesfloat(fi,_,_) -> fi
  | TmAscribe(fi,_,_) -> fi
  | TmString(fi,_) -> fi
  | TmUnit(fi) -> fi
  | TmInert(fi,_) -> fi
  | TmFix(fi,_) -> fi
  | TmTAbs(fi,_,_,_) -> fi
  | TmTApp(fi,_, _) -> fi
  | TmTag(fi,_,_,_) -> fi
  | TmCase(fi,_,_) -> fi
  | TmLoc(fi,_) -> fi
  | TmRef(fi,_) -> fi
  | TmDeref(fi,_) -> fi
  | TmAssign(fi,_,_) -> fi
  | TmError(fi) -> fi
  | TmTry(fi,_,_) -> fi
  | TmZero(fi) -> fi
  | TmSucc(fi,_) -> fi
  | TmPred(fi,_) -> fi
  | TmIsZero(fi,_) -> fi
  | TmPack(fi,_,_,_) -> fi
  | TmUnpack(fi,_,_,_,_) -> fi 

(* ---------------------------------------------------------------------- *)
(* Printing *)

(* The printing functions call these utility functions to insert grouping
  information and line-breaking hints for the pretty-printing library:
     obox   Open a "box" whose contents will be indented by two spaces if
            the whole box cannot fit on the current line
     obox0  Same but indent continuation lines to the same column as the
            beginning of the box rather than 2 more columns to the right
     cbox   Close the current box
     break  Insert a breakpoint indicating where the line maybe broken if
            necessary.
  See the documentation for the Format module in the OCaml library for
  more details. 
*)

let obox0() = open_hvbox 0
let obox() = open_hvbox 2
let cbox() = close_box()
let break() = print_break 0 0

let small t = 
  match t with
    TmVar(_,_,_) -> true
  | _ -> false

let rec printkn_kind outer ctx k = match k with
      knK -> printkn_arrowkind outer ctx knK

and printkn_arrowkind outer ctx k = match k with
    KnArr(knK1,knK2) ->
      obox0(); 
      printkn_akind false ctx knK1;
      if outer then pr " ";
      pr "=>";
      if outer then print_space() else break();
      printkn_arrowkind outer ctx knK2;
      cbox()
  | knK -> printkn_akind outer ctx knK

and printkn_akind outer ctx k = match k with 
    KnStar -> pr "*"
  | knK -> pr "("; printkn_kind outer ctx knK; pr ")"

let printkn ctx knK = printkn_kind true ctx knK

let prokn ctx knK =
  if knK <> KnStar then (pr "::"; printkn_kind false ctx knK)

let rec printty_Type outer ctx tyT = match tyT with
    TyAll(tyX,tyT1,tyT2) ->
      let (ctx1,tyX) = (pickfreshname ctx tyX) in
      obox(); pr "All "; pr tyX;
      proty ctx tyT1;
      pr ".";
      print_space ();
      printty_Type outer ctx1 tyT2;
      cbox()
  | TyRef(tyT) -> pr "Ref "; printty_AType false ctx tyT
  | TySource(tyT) -> pr "Source "; printty_AType false ctx tyT
  | TySink(tyT) -> pr "Sink "; printty_AType false ctx tyT
  | TyAbs(tyX,knK1,tyT2) ->
      let (ctx',x') = (pickfreshname ctx tyX) in
      obox(); pr "lambda ";
      pr x'; prokn ctx knK1;
      pr "."; if outer then print_space() else break();
      printty_Type outer ctx' tyT2;
      cbox()
  | tyT -> printty_ArrowType outer ctx tyT

and printty_ArrowType outer ctx  tyT = match tyT with 
    TyArr(tyT1,tyT2) ->
      obox0(); 
      printty_AppType false ctx tyT1;
      if outer then pr " ";
      pr "->";
      if outer then print_space() else break();
      printty_ArrowType outer ctx tyT2;
      cbox()
  | tyT -> printty_AppType outer ctx tyT

and proty ctx tyS =
  if tyS <> TyTop then (pr "<:"; printty_Type false ctx tyS)

and printty_AppType outer ctx k = match k with 
    TyApp(tyT1,tyT2) ->
      obox0();
      printty_AppType false ctx tyT1;
      print_space();
      printty_AType false ctx tyT2;
      cbox()
  | tyT -> printty_AType outer ctx tyT

and printty_AType outer ctx tyT = match tyT with
    TyId(b) -> pr b
  | TyVar(x,n) ->
      if ctxlength ctx = n then
        pr (index2name dummyinfo ctx x)
      else
        pr ("[bad index: " ^ (string_of_int x) ^ "/" ^ (string_of_int n)
            ^ " in {"
            ^ (List.fold_left (fun s (x,_) -> s ^ " " ^ x) "" ctx)
            ^ " }]")
  | TyBool -> pr "Bool"
  | TyTop -> pr "Top"
  | TyBot -> pr "Bot"
  | TyRecord(fields) ->
        let pf i (li,tyTi) =
          if (li <> ((string_of_int i))) then (pr li; pr ":"); 
          printty_Type false ctx tyTi 
        in let rec p i l = match l with 
            [] -> ()
          | [f] -> pf i f
          | f::rest ->
              pf i f; pr","; if outer then print_space() else break(); 
              p (i+1) rest
        in pr "{"; open_hovbox 0; p 1 fields; pr "}"; cbox()
  | TyVariant(fields) ->
        let pf i (li,tyTi) =
          if (li <> ((string_of_int i))) then (pr li; pr ":"); 
          printty_Type false ctx tyTi 
        in let rec p i l = match l with
            [] -> ()
          | [f] -> pf i f
          | f::rest ->
              pf i f; pr","; if outer then print_space() else break(); 
              p (i+1) rest
        in pr "<"; open_hovbox 0; p 1 fields; pr ">"; cbox()
  | TyFloat -> pr "Float"
  | TyString -> pr "String"
  | TyUnit -> pr "Unit"
  | TyNat -> pr "Nat"
  | TySome(tyX,tyT1,tyT2) ->
      let (ctx1,tyX) = pickfreshname ctx tyX in
      obox();
      pr "{Some "; pr tyX;
      proty ctx tyT1;
      pr ",";
      if outer then print_space() else break();
      printty_Type false ctx1 tyT2; pr "}";
      cbox()
  | tyT -> pr "("; printty_Type outer ctx tyT; pr ")"

let printty ctx tyT = printty_Type true ctx tyT 

let rec printtm_Term outer ctx t = match t with
    TmAbs(fi,x,tyT1,t2) ->
      (let (ctx',x') = (pickfreshname ctx x) in
         obox(); pr "lambda ";
         pr x'; pr ":"; printty_Type false ctx tyT1; pr ".";
         if (small t2) && not outer then break() else print_space();
         printtm_Term outer ctx' t2;
         cbox())
  | TmIf(fi, t1, t2, t3) ->
       obox0();
       pr "if ";
       printtm_Term false ctx t1;
       print_space();
       pr "then ";
       printtm_Term false ctx t2;
       print_space();
       pr "else ";
       printtm_Term false ctx t3;
       cbox()
  | TmLet(fi, x, t1, t2) ->
       obox0();
       pr "let "; pr x; pr " = "; 
       printtm_Term false ctx t1;
       print_space(); pr "in"; print_space();
       printtm_Term false (addname ctx x) t2;
       cbox()
  | TmFix(fi, t1) ->
       obox();
       pr "fix "; 
       printtm_Term false ctx t1;
       cbox()
  | TmCase(_, t, cases) ->
      obox();
      pr "case "; printtm_Term false ctx t; pr " of";
      print_space();
      let pc (li,(xi,ti)) = let (ctx',xi') = (pickfreshname ctx xi) in
                              pr "<"; pr li; pr "="; pr xi'; pr ">==>"; 
                              printtm_Term false ctx' ti 
      in let rec p l = match l with 
            [] -> ()
          | [c] -> pc c
          | c::rest -> pc c; print_space(); pr "| "; p rest
      in p cases;
      cbox()
  | TmAssign(fi, t1, t2) ->
       obox();
       printtm_AppTerm false ctx t1;
       pr " := ";
       printtm_AppTerm false ctx t2;
       cbox()
  | TmTry(fi, t1, t2) ->
       obox0();
       pr "try ";
       printtm_Term false ctx t1;
       print_space();
       pr "with ";
       printtm_Term false ctx t2;
       cbox()
  | TmTAbs(fi,x,tyS,t) ->
      (let (ctx1,x) = (pickfreshname ctx x) in
               obox(); pr "lambda "; pr x;
               proty ctx tyS;
               pr ".";
               if (small t) && not outer then break() else print_space();
               printtm_Term outer ctx1 t;
               cbox())
  | TmUnpack(fi,tyX,x,t1,t2) ->
      (let (ctx',tyX) = (pickfreshname ctx tyX) in
      let (ctx',x) = (pickfreshname ctx' x) in
      obox(); pr "let {"; pr tyX; pr ","; pr x; pr "} ="; print_space();
      printtm_Term false ctx t1; pr " in ";
      printtm_Term outer ctx' t2; cbox())
  | t -> printtm_AppTerm outer ctx t

and printtm_AppTerm outer ctx t = match t with
    TmApp(fi, t1, t2) ->
      obox0();
      printtm_AppTerm false ctx t1;
      print_space();
      printtm_ATerm false ctx t2;
      cbox()
  | TmRef(fi, t1) ->
       obox();
       pr "ref ";
       printtm_ATerm false ctx t1;
       cbox()
  | TmDeref(fi, t1) ->
       obox();
       pr "!";
       printtm_ATerm false ctx t1;
       cbox()
  | TmTimesfloat(_,t1,t2) ->
       pr "timesfloat "; printtm_ATerm false ctx t2; 
       pr " "; printtm_ATerm false ctx t2
  | TmTApp(fi,t,tyS) ->
      obox0();
      printtm_AppTerm false ctx t;
      print_space();
      pr "["; printty_Type false ctx tyS; pr "]";
      cbox()
  | TmPred(_,t1) ->
       pr "pred "; printtm_ATerm false ctx t1
  | TmIsZero(_,t1) ->
       pr "iszero "; printtm_ATerm false ctx t1
  | t -> printtm_PathTerm outer ctx t

and printtm_PathTerm outer ctx t = match t with
    TmProj(_, t1, l) ->
      printtm_ATerm false ctx t1; pr "."; pr l
  | t -> printtm_AscribeTerm outer ctx t

and printtm_AscribeTerm outer ctx t = match t with
    TmAscribe(_,t1,tyT1) ->
      obox0();
      printtm_AppTerm false ctx t1;
      print_space(); pr "as ";
      printty_Type false ctx tyT1;
      cbox()
  | t -> printtm_ATerm outer ctx t

and printtm_ATerm outer ctx t = match t with
    TmVar(fi,x,n) ->
      if ctxlength ctx = n then
        pr (index2name fi ctx x)
      else
        pr ("[bad index: " ^ (string_of_int x) ^ "/" ^ (string_of_int n)
            ^ " in {"
            ^ (List.fold_left (fun s (x,_) -> s ^ " " ^ x) "" ctx)
            ^ " }]")
  | TmTrue(_) -> pr "true"
  | TmFalse(_) -> pr "false"
  | TmRecord(fi, fields) ->
       let pf i (li,ti) =
         if (li <> ((string_of_int i))) then (pr li; pr "="); 
         printtm_Term false ctx ti 
       in let rec p i l = match l with
           [] -> ()
         | [f] -> pf i f
         | f::rest ->
             pf i f; pr","; if outer then print_space() else break(); 
             p (i+1) rest
       in pr "{"; open_hovbox 0; p 1 fields; pr "}"; cbox()
  | TmTag(fi, l, t, tyT) ->
      obox();
      pr "<"; pr l; pr "="; printtm_Term false ctx t; pr ">";
      print_space();
      pr "as "; printty_Type outer ctx tyT;
      cbox();
  | TmFloat(_,s) -> pr (string_of_float s)
  | TmString(_,s) -> pr ("\"" ^ s ^ "\"")
  | TmUnit(_) -> pr "unit"
  | TmInert(_,tyT) -> pr "inert["; printty_Type false ctx tyT; pr "]"
  | TmLoc(fi, l) ->
       pr "<loc #"; print_int l; pr">"
  | TmError(_) -> pr "error"
  | TmZero(fi) ->
       pr "0"
  | TmSucc(_,t1) ->
     let rec f n t = match t with
         TmZero(_) -> pr (string_of_int n)
       | TmSucc(_,s) -> f (n+1) s
       | _ -> (pr "(succ "; printtm_ATerm false ctx t1; pr ")")
     in f 1 t1
  | TmPack(fi,tyT1,t2,tyT3) ->
      obox(); pr "{*"; printty_Type false ctx tyT1;
      pr ","; if outer then print_space() else break();
      printtm_Term false ctx t2;
      pr "}"; print_space(); pr "as ";
      printty_Type outer ctx tyT3;
      cbox()
  | t -> pr "("; printtm_Term outer ctx t; pr ")"

let printtm ctx t = printtm_Term true ctx t 

let prbinding ctx b = match b with
    NameBind -> ()
  | TyVarBind(tyS) -> pr "<: ";printty_Type false ctx tyS
  | VarBind(tyT) -> pr ": "; printty ctx tyT
  | TyAbbBind(tyT,_) -> pr "= "; printty ctx tyT
  | TmAbbBind(t,tyT) -> pr "= "; printtm ctx t 


