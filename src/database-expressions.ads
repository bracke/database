--  Ada-native deterministic expression trees used by checks, generated columns,
--  partial indexes, expression indexes, views, and materialized views.
with Ada.Containers.Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Values;

--  Typed expression descriptors used by constraints, views, and indexes.
package Database.Expressions is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Expression_Kind defines a public database type used by this package.
   type Expression_Kind is
     (Literal_Expr,
      Column_Expr,
      Add_Expr,
      Subtract_Expr,
      Multiply_Expr,
      Divide_Expr,
      Equal_Expr,
      Not_Equal_Expr,
      Less_Expr,
      Less_Or_Equal_Expr,
      Greater_Expr,
      Greater_Or_Equal_Expr,
      And_Expr,
      Or_Expr,
      Not_Expr,
      Is_Null_Expr,
      Is_Not_Null_Expr,
      Function_Expr,
      Registered_Function_Expr);

   --  Deterministic_Function defines a public database type used by this package.
   type Deterministic_Function is
     (Lowercase_Text,
      Text_Length,
      Integer_Abs,
      Concat_Text);

   --  Expression defines a public database type used by this package.
   type Expression_Node is private;
   type Expression_Node_Access is access Expression_Node;

   type Expression is record
      Node : Expression_Node_Access;
   end record;

   --  Compares two expression handles for structural identity.
   --  @param Left Left expression operand.
   --  @param Right Right expression operand.
   --  @return True when both expressions refer to the same expression structure.
   overriding function "=" (Left, Right : Expression) return Boolean;

   --  Expression_Vectors stores ordered expression values for this package.
   package Expression_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Expression);

   --  Return literal for the supplied database state or arguments.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Literal (Value : Database.Values.Value) return Expression;
   --  Return column for the supplied database state or arguments.
   --  @param Column_Id column id argument supplied to the operation.
   --  @return Result produced by the function.
   function Column (Column_Id : Natural) return Expression;
   --  Return binary for the supplied database state or arguments.
   --  @param Kind kind selector controlling the operation.
   --  @param Left left argument supplied to the operation.
   --  @param Right right argument supplied to the operation.
   --  @return Result produced by the function.
   function Binary (Kind : Expression_Kind; Left, Right : Expression) return Expression;
   --  Return unary for the supplied database state or arguments.
   --  @param Kind kind selector controlling the operation.
   --  @param Operand operand argument supplied to the operation.
   --  @return Result produced by the function.
   function Unary (Kind : Expression_Kind; Operand : Expression) return Expression;
   --  Return function call for the supplied database state or arguments.
   --  @param Func func argument supplied to the operation.
   --  @param Args args argument supplied to the operation.
   --  @return Result produced by the function.
   function Function_Call
     (Func : Deterministic_Function;
      Args : Expression_Vectors.Vector) return Expression;

   --  Return registered function call for the supplied database state or arguments.
   --  @param Name logical name of the object.
   --  @param Args args argument supplied to the operation.
   --  @return Status result describing whether the operation succeeded.
   function Registered_Function_Call
     (Name : Wide_Wide_String;
      Args : Expression_Vectors.Vector) return Expression;

   --  Return kind of for the supplied database state or arguments.
   --  @param Expr expr argument supplied to the operation.
   --  @return Result produced by the function.
   function Kind_Of (Expr : Expression) return Expression_Kind;
   --  Return is deterministic for the supplied database state or arguments.
   --  @param Expr expr argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Deterministic (Expr : Expression) return Boolean;
   --  Return depends on column for the supplied database state or arguments.
   --  @param Expr expr argument supplied to the operation.
   --  @param Column_Id column id argument supplied to the operation.
   --  @return Result produced by the function.
   function Depends_On_Column (Expr : Expression; Column_Id : Natural) return Boolean;

   --  Return evaluate for the supplied database state or arguments.
   --  @param Expr expr argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @param Value typed value supplied to the operation.
   --  @return Result produced by the function.
   function Evaluate
     (Expr   : Expression;
      Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row;
      Value  : out Database.Values.Value) return Database.Status.Result;

   --  Return evaluate boolean for the supplied database state or arguments.
   --  @param Expr expr argument supplied to the operation.
   --  @param Schema schema metadata used for validation or registration.
   --  @param Row row value supplied to or returned by the operation.
   --  @param Result output value populated by the operation.
   --  @return Result produced by the function.
   function Evaluate_Boolean
     (Expr   : Expression;
      Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row;
      Result : out Boolean) return Database.Status.Result;

   --  Stable, deterministic expression metadata encoding used by the durable
   --  catalog for relational objects. The format is explicit text, not Ada
   --  memory layout, and is intentionally limited to deterministic
   --  expressions that are safe for persistent schema metadata.
   --  @param Expr expr argument supplied to the operation.
   --  @return Result produced by the function.
   function Persistent_Image (Expr : Expression) return Wide_Wide_String;

   --  Return from persistent image for the supplied database state or arguments.
   --  @param Text text argument supplied to the operation.
   --  @param Expr expr argument supplied to the operation.
   --  @return Result produced by the function.
   function From_Persistent_Image
     (Text : Wide_Wide_String;
      Expr : out Expression) return Database.Status.Result;

private
   --  Expression_Node stores the internal expression tree representation.
   --  This record is intentionally not discriminated because it contains
   --  vector components and is copied as a mutable tree node by constructors.
   type Expression_Node is record
      Kind            : Expression_Kind := Literal_Expr;
      Literal_Value   : Database.Values.Value := Database.Values.Null_Value;
      Column_Id       : Natural := 0;
      Left            : Expression_Node_Access := null;
      Right           : Expression_Node_Access := null;
      Operand         : Expression_Node_Access := null;
      Func            : Deterministic_Function := Lowercase_Text;
      Args            : Expression_Vectors.Vector;
      Function_Name   : Unbounded_Wide_Wide_String;
      Registered_Args : Expression_Vectors.Vector;
   end record;
end Database.Expressions;
