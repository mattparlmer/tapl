(* module Syntax: syntax trees and associated support functions *)

open Support.Pervasive
open Support.Error

(* Data type definitions *)
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

type command =
    Import of string
  | Eval of info * term
  | Bind of info * string * binding
  | SomeBind of info * string * string * term

(* Contexts *)
type context
val emptycontext : context 
val ctxlength : context -> int
val addbinding : context -> string -> binding -> context
val addname: context -> string -> context
val index2name : info -> context -> int -> string
val getbinding : info -> context -> int -> binding
val name2index : info -> context -> string -> int
val isnamebound : context -> string -> bool
val getTypeFromContext : info -> context -> int -> ty

(* Shifting and substitution *)
val termShift: int -> term -> term
val termSubstTop: term -> term -> term
val typeShift : int -> ty -> ty
val typeSubstTop: ty -> ty -> ty
val tytermSubstTop: ty -> term -> term

(* Printing *)
val printtm: context -> term -> unit
val printtm_ATerm: bool -> context -> term -> unit
val printty : context -> ty -> unit
val printkn : context -> kind -> unit
val prbinding : context -> binding -> unit

(* Misc *)
val tmInfo: term -> info
val maketop: kind -> ty

