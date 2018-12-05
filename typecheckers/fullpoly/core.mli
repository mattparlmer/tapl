(* module Core

   Core typechecking and evaluation functions
*)

open Syntax
open Support.Error

val eval : context -> term -> term 
val typeof : context -> term -> ty
val tyeqv : context -> ty -> ty -> bool
val simplifyty : context -> ty -> ty
val evalbinding : context -> binding -> binding 
