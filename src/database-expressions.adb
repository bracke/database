with Ada.Characters.Conversions;
with Ada.Containers;
with Ada.Strings.Wide_Wide_Unbounded;
use Ada.Strings.Wide_Wide_Unbounded;
with Database.Types;
with Database.Functions;
with Database.Date_Time;
with Database.Ordering;

package body Database.Expressions is
   use type Ada.Containers.Count_Type;
   use type Database.Types.Value_Kind;

   overriding function "=" (Left, Right : Expression) return Boolean is
   begin
      return Left.Node = Right.Node;
   end "=";
   function Clone (Expr : Expression) return Expression_Node_Access;

   function Clone (Expr : Expression) return Expression_Node_Access is
      Args : Expression_Vectors.Vector;
   begin
      if Expr.Node = null then
         return new Expression_Node'
           (Kind          => Literal_Expr,
            Literal_Value => Database.Values.Null_Value,
            others        => <>);
      end if;
      case Expr.Node.Kind is
         when Literal_Expr =>
            return new Expression_Node'
              (Kind          => Literal_Expr,
               Literal_Value => Expr.Node.Literal_Value,
               others        => <>);
         when Column_Expr =>
            return new Expression_Node'
              (Kind      => Column_Expr,
               Column_Id => Expr.Node.Column_Id,
               others    => <>);
         when Add_Expr | Subtract_Expr | Multiply_Expr | Divide_Expr |
              Equal_Expr | Not_Equal_Expr | Less_Expr | Less_Or_Equal_Expr |
              Greater_Expr | Greater_Or_Equal_Expr | And_Expr | Or_Expr =>
            return new Expression_Node'
              (Kind   => Expr.Node.Kind,
               Left   => Clone ((Node => Expr.Node.Left)),
               Right  => Clone ((Node => Expr.Node.Right)),
               others => <>);
         when Not_Expr | Is_Null_Expr | Is_Not_Null_Expr =>
            return new Expression_Node'
              (Kind    => Expr.Node.Kind,
               Operand => Clone ((Node => Expr.Node.Operand)),
               others  => <>);
         when Function_Expr =>
            for A of Expr.Node.Args loop
               Args.Append (Expression'(Node => Clone (A)));
            end loop;
            return new Expression_Node'
              (Kind   => Function_Expr,
               Func   => Expr.Node.Func,
               Args   => Args,
               others => <>);
         when Registered_Function_Expr =>
            for A of Expr.Node.Registered_Args loop
               Args.Append (Expression'(Node => Clone (A)));
            end loop;
            return new Expression_Node'
              (Kind            => Registered_Function_Expr,
               Function_Name   => Expr.Node.Function_Name,
               Registered_Args => Args,
               others          => <>);
      end case;
   end Clone;

   function Literal (Value : Database.Values.Value) return Expression is
   begin
      return (Node => new Expression_Node'
        (Kind          => Literal_Expr,
         Literal_Value => Value,
         others        => <>));
   end Literal;

   function Column (Column_Id : Natural) return Expression is
   begin
      return (Node => new Expression_Node'
        (Kind      => Column_Expr,
         Column_Id => Column_Id,
         others    => <>));
   end Column;

   function Binary (Kind : Expression_Kind; Left, Right : Expression) return Expression is
   begin
      return (Node => new Expression_Node'
        (Kind   => Kind,
         Left   => Clone (Left),
         Right  => Clone (Right),
         others => <>));
   end Binary;

   function Unary (Kind : Expression_Kind; Operand : Expression) return Expression is
   begin
      return (Node => new Expression_Node'
        (Kind    => Kind,
         Operand => Clone (Operand),
         others  => <>));
   end Unary;

   function Function_Call
     (Func : Deterministic_Function;
      Args : Expression_Vectors.Vector) return Expression is
      Stored : Expression_Vectors.Vector;
   begin
      for A of Args loop
         Stored.Append (Expression'(Node => Clone (A)));
      end loop;
      return (Node => new Expression_Node'
        (Kind   => Function_Expr,
         Func   => Func,
         Args   => Stored,
         others => <>));
   end Function_Call;

   function Registered_Function_Call
     (Name : Wide_Wide_String;
      Args : Expression_Vectors.Vector) return Expression is
      Stored : Expression_Vectors.Vector;
   begin
      for A of Args loop
         Stored.Append (Expression'(Node => Clone (A)));
      end loop;
      return  (Node => new Expression_Node'
        (Kind            => Registered_Function_Expr,
         Function_Name   => To_Unbounded_Wide_Wide_String (Name),
         Registered_Args => Stored,
         others          => <>));
   end Registered_Function_Call;

   function Kind_Of (Expr : Expression) return Expression_Kind is
   begin
      if Expr.Node = null then
         return Literal_Expr;
      end if;
      return Expr.Node.Kind;
   end Kind_Of;

   function Is_Deterministic (Expr : Expression) return Boolean is
   begin
      if Expr.Node = null then
         return True;
      end if;
      case Expr.Node.Kind is
         when Literal_Expr | Column_Expr => return True;
         when Function_Expr =>
            for A of Expr.Node.Args loop
               if not Is_Deterministic (A) then
                  return False;
               end if;
            end loop;
            return True;
         when Registered_Function_Expr =>
            if not Database.Status.Is_Ok (Database.Functions.Validate_Persistent_Use (
              To_Wide_Wide_String (Expr.Node.Function_Name))) then
               return False;
            end if;
            for A of Expr.Node.Registered_Args loop
               if not Is_Deterministic (A) then
                  return False;
               end if;
            end loop;
            return True;
         when Not_Expr | Is_Null_Expr | Is_Not_Null_Expr =>
            return Is_Deterministic ((Node => Expr.Node.Operand));
         when others =>
            return Is_Deterministic ((Node => Expr.Node.Left)) and then
                   Is_Deterministic ((Node => Expr.Node.Right));
      end case;
   end Is_Deterministic;

   function Depends_On_Column (Expr : Expression; Column_Id : Natural) return Boolean is
   begin
      if Expr.Node = null then
         return False;
      end if;
      case Expr.Node.Kind is
         when Column_Expr => return Expr.Node.Column_Id = Column_Id;
         when Literal_Expr => return False;
         when Function_Expr =>
            for A of Expr.Node.Args loop
               if Depends_On_Column (A, Column_Id) then
                  return True;
               end if;
            end loop;
            return False;
         when Registered_Function_Expr =>
            for A of Expr.Node.Registered_Args loop
               if Depends_On_Column (A, Column_Id) then
                  return True;
               end if;
            end loop;
            return False;
         when Not_Expr | Is_Null_Expr | Is_Not_Null_Expr =>
            return Depends_On_Column ((Node => Expr.Node.Operand), Column_Id);
         when others =>
            return Depends_On_Column ((Node => Expr.Node.Left), Column_Id) or else
                   Depends_On_Column ((Node => Expr.Node.Right), Column_Id);
      end case;
   end Depends_On_Column;

   function Position_For (Schema : Database.Schema.Table_Schema; Column_Id : Natural) return Natural is
   begin
      return Database.Schema.Find_Column_Id_Position (Schema, Column_Id);
   end Position_For;

   function Compare_Int (K : Expression_Kind; L, R : Integer) return Boolean is
   begin
      case K is
         when Equal_Expr => return L = R;
         when Not_Equal_Expr => return L /= R;
         when Less_Expr => return L < R;
         when Less_Or_Equal_Expr => return L <= R;
         when Greater_Expr => return L > R;
         when Greater_Or_Equal_Expr => return L >= R;
         when others => return False;
      end case;
   end Compare_Int;

   function Evaluate
     (Expr   : Expression;
      Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row;
      Value  : out Database.Values.Value) return Database.Status.Result is
      L, R : Database.Values.Value;
      B1, B2 : Boolean := False;
      Res : Database.Status.Result;
   begin
      if Expr.Node = null then
         Value := Database.Values.Null_Value;
         return Database.Status.Success;
      end if;

      case Expr.Node.Kind is
         when Literal_Expr =>
            Value := Expr.Node.Literal_Value;
            return Database.Status.Success;
         when Column_Expr =>
            declare
               P : constant Natural := Position_For (Schema, Expr.Node.Column_Id);
            begin
               if P >= Database.Rows.Column_Count (Row) then
                  Value := Database.Values.Null_Value;
                  return Database.Status.Failure (Database.Status.Invalid_Argument, "column reference out of range");
               end if;
               Value := Database.Rows.Get (Row, P);
               return Database.Status.Success;
            end;
         when Add_Expr | Subtract_Expr | Multiply_Expr | Divide_Expr =>
            Res := Evaluate  ((Node => Expr.Node.Left),
              Schema,
              Row,
              L);
              if not Database.Status.Is_Ok (Res) then
                 return Res;
              end if;
            Res := Evaluate  ((Node => Expr.Node.Right),
              Schema,
              Row,
              R);
              if not Database.Status.Is_Ok (Res) then
                 return Res;
              end if;
            if L.Kind = Database.Types.Integer_Value and then R.Kind = Database.Types.Integer_Value then
               case Expr.Node.Kind is
                  when Add_Expr => Value := Database.Values.From_Integer (L.Int + R.Int);
                  when Subtract_Expr => Value := Database.Values.From_Integer (L.Int - R.Int);
                  when Multiply_Expr => Value := Database.Values.From_Integer (L.Int * R.Int);
                  when Divide_Expr =>
                     if R.Int = 0 then
                        Value := Database.Values.Null_Value;
                        else
                           Value := Database.Values.From_Integer (L.Int / R.Int);
                     end if;
                  when others => null;
               end case;
            elsif Expr.Node.Kind = Add_Expr and then L.Kind = Database.Types.Date_Time_Value
              and then R.Kind = Database.Types.Duration_Value then
               Value := Database.Values.From_Date_Time (Database.Date_Time.Add (L.Date_Time, R.Time_Span));
            elsif Expr.Node.Kind = Subtract_Expr and then L.Kind = Database.Types.Date_Time_Value
              and then R.Kind = Database.Types.Date_Time_Value then
               Value := Database.Values.From_Duration (Database.Date_Time.Difference (L.Date_Time, R.Date_Time));
            else
               Value := Database.Values.Null_Value;
               return Database.Status.Failure (Database.Status.Invalid_Argument,
                 "arithmetic expression requires compatible typed operands");
            end if;
            return Database.Status.Success;
         when Equal_Expr | Not_Equal_Expr | Less_Expr | Less_Or_Equal_Expr | Greater_Expr | Greater_Or_Equal_Expr =>
            Res := Evaluate  ((Node => Expr.Node.Left),
              Schema,
              Row,
              L);
              if not Database.Status.Is_Ok (Res) then
                 return Res;
              end if;
            Res := Evaluate  ((Node => Expr.Node.Right),
              Schema,
              Row,
              R);
              if not Database.Status.Is_Ok (Res) then
                 return Res;
              end if;
            if L.Kind = Database.Types.Null_Value or else R.Kind = Database.Types.Null_Value then
               Value := Database.Values.From_Boolean (False);
            elsif L.Kind = Database.Types.Integer_Value and then R.Kind = Database.Types.Integer_Value then
               Value := Database.Values.From_Boolean (Compare_Int (Expr.Node.Kind, L.Int, R.Int));
            else
               declare
                  C : constant Integer := Database.Ordering.Compare (L, R);
               begin
                  case Expr.Node.Kind is
                     when Equal_Expr => Value := Database.Values.From_Boolean (Database.Values.Equal (L, R));
                     when Not_Equal_Expr => Value := Database.Values.From_Boolean (not Database.Values.Equal (L, R));
                     when Less_Expr => Value := Database.Values.From_Boolean (C < 0);
                     when Less_Or_Equal_Expr => Value := Database.Values.From_Boolean (C <= 0);
                     when Greater_Expr => Value := Database.Values.From_Boolean (C > 0);
                     when Greater_Or_Equal_Expr => Value := Database.Values.From_Boolean (C >= 0);
                     when others => null;
                  end case;
               end;
            end if;
            return Database.Status.Success;
         when And_Expr | Or_Expr =>
            Res := Evaluate_Boolean  ((Node => Expr.Node.Left),
              Schema,
              Row,
              B1);
              if not Database.Status.Is_Ok (Res) then
                 return Res;
              end if;
            Res := Evaluate_Boolean  ((Node => Expr.Node.Right),
              Schema,
              Row,
              B2);
              if not Database.Status.Is_Ok (Res) then
                 return Res;
              end if;
            if Expr.Node.Kind = And_Expr then
               Value := Database.Values.From_Boolean (B1 and B2);
               else
                  Value := Database.Values.From_Boolean (B1 or B2);
            end if;
            return Database.Status.Success;
         when Not_Expr =>
            Res := Evaluate_Boolean  ((Node => Expr.Node.Operand),
              Schema,
              Row,
              B1);
              if not Database.Status.Is_Ok (Res) then
                 return Res;
              end if;
            Value := Database.Values.From_Boolean (not B1);
            return Database.Status.Success;
         when Is_Null_Expr | Is_Not_Null_Expr =>
            Res := Evaluate  ((Node => Expr.Node.Operand),
              Schema,
              Row,
              L);
              if not Database.Status.Is_Ok (Res) then
                 return Res;
              end if;
            Value  :=
              Database.Values.From_Boolean ((L.Kind = Database.Types.Null_Value) = (Expr.Node.Kind = Is_Null_Expr));
            return Database.Status.Success;
         when Registered_Function_Expr =>
            declare
               Args : Database.Values.Value_Vector;
               AVal : Database.Values.Value;
            begin
               for A of Expr.Node.Registered_Args loop
                  Res := Evaluate (A, Schema, Row, AVal);
                  if not Database.Status.Is_Ok (Res) then
                     return Res;
                  end if;
                  Args.Append (AVal);
               end loop;
               return Database.Functions.Evaluate (To_Wide_Wide_String (Expr.Node.Function_Name), Args, Value);
            end;
         when Function_Expr =>
            case Expr.Node.Func is
               when Lowercase_Text =>
                  if Expr.Node.Args.Length /= 1 then
                     Value := Database.Values.Null_Value;
                     return Database.Status.Failure (Database.Status.Invalid_Argument,
                       "lowercase expects one argument");
                  end if;
                  Res := Evaluate  (Expr.Node.Args.Element (0),
                    Schema,
                    Row,
                    L);
                    if not Database.Status.Is_Ok (Res) then
                       return Res;
                    end if;
                  if L.Kind /= Database.Types.Text_Value then
                     Value := Database.Values.Null_Value;
                     return Database.Status.Failure (Database.Status.Invalid_Argument, "lowercase expects text");
                  end if;
                  declare
                     S : Wide_Wide_String := To_Wide_Wide_String (L.Text);
                  begin
                     for I in S'Range loop
                        if S (I) in 'A' .. 'Z' then
                           S (I) := Wide_Wide_Character'Val (Wide_Wide_Character'Pos (S (I)) + 32);
                        end if;
                     end loop;
                     Value := Database.Values.From_Text (S);
                  end;
               when Text_Length =>
                  Res := Evaluate  (Expr.Node.Args.Element (0),
                    Schema,
                    Row,
                    L);
                    if not Database.Status.Is_Ok (Res) then
                       return Res;
                    end if;
                  if L.Kind /= Database.Types.Text_Value then
                     Value := Database.Values.Null_Value;
                     return Database.Status.Failure (Database.Status.Invalid_Argument, "length expects text");
                  end if;
                  Value := Database.Values.From_Integer (To_Wide_Wide_String (L.Text)'Length);
               when Integer_Abs =>
                  Res := Evaluate  (Expr.Node.Args.Element (0),
                    Schema,
                    Row,
                    L);
                    if not Database.Status.Is_Ok (Res) then
                       return Res;
                    end if;
                  if L.Kind /= Database.Types.Integer_Value then
                     Value := Database.Values.Null_Value;
                     return Database.Status.Failure (Database.Status.Invalid_Argument, "abs expects integer");
                  end if;
                  Value := Database.Values.From_Integer (abs L.Int);
               when Concat_Text =>
                  Res := Evaluate  (Expr.Node.Args.Element (0),
                    Schema,
                    Row,
                    L);
                    if not Database.Status.Is_Ok (Res) then
                       return Res;
                    end if;
                  Res := Evaluate  (Expr.Node.Args.Element (1),
                    Schema,
                    Row,
                    R);
                    if not Database.Status.Is_Ok (Res) then
                       return Res;
                    end if;
                  if L.Kind /= Database.Types.Text_Value or else R.Kind /= Database.Types.Text_Value then
                     Value := Database.Values.Null_Value;
                     return Database.Status.Failure (Database.Status.Invalid_Argument, "concat expects text");
                  end if;
                  Value := Database.Values.From_Text (To_Wide_Wide_String (L.Text) & To_Wide_Wide_String (R.Text));
            end case;
            return Database.Status.Success;
      end case;
   end Evaluate;

   function Evaluate_Boolean
     (Expr   : Expression;
      Schema : Database.Schema.Table_Schema;
      Row    : Database.Rows.Row;
      Result : out Boolean) return Database.Status.Result is
      V : Database.Values.Value;
      R : Database.Status.Result;
   begin
      R := Evaluate (Expr, Schema, Row, V);
      if not Database.Status.Is_Ok (R) then
         Result := False;
         return R;
      end if;
      if V.Kind /= Database.Types.Boolean_Value then
         Result := False;
         return Database.Status.Failure (Database.Status.Invalid_Argument, "expression did not evaluate to boolean");
      end if;
      Result := V.Bool;
      return Database.Status.Success;
   end Evaluate_Boolean;

   function N_Image (N : Natural) return Wide_Wide_String is
      S : constant Wide_Wide_String := Natural'Wide_Wide_Image (N);
   begin
      if S'Length > 0 and then S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      end if;
      return S;
   end N_Image;

   function I_Image (I : Integer) return Wide_Wide_String is
      S : constant Wide_Wide_String := Integer'Wide_Wide_Image (I);
   begin
      if S'Length > 0 and then S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      end if;
      return S;
   end I_Image;

   function Escape_Text (S : Wide_Wide_String) return Wide_Wide_String is
      R : Unbounded_Wide_Wide_String;
   begin
      for Ch of S loop
         if Ch = '\' or else Ch = ':' or else Ch = '[' or else Ch = ']' then
            Append (R, '\');
         end if;
         Append (R, Ch);
      end loop;
      return To_Wide_Wide_String (R);
   end Escape_Text;

   function Persistent_Value_Image (V : Database.Values.Value) return Wide_Wide_String is
   begin
      case V.Kind is
         when Database.Types.Null_Value => return "Z";
         when Database.Types.Boolean_Value => return "B:" & (if V.Bool then "1" else "0");
         when Database.Types.Integer_Value => return "I:" & I_Image (V.Int);
         when Database.Types.Long_Integer_Value => return "L:" & Long_Long_Integer'Wide_Wide_Image (V.Long_Int);
         when Database.Types.Text_Value => return "T:" & Escape_Text (To_Wide_Wide_String (V.Text));
         when Database.Types.Enum_Value => return "E:" & Escape_Text (To_Wide_Wide_String (V.Enum_Text));
         when Database.Types.Array_Value => return "A:" & Escape_Text (To_Wide_Wide_String (V.Array_Text));
         when others =>
            --  Rare value kinds are represented as NULL in persistent expression
            --  metadata unless future phases add specialized codecs. This keeps
            --  durable schema metadata deterministic and rejectable by callers
            --  through Validate_Definition for non-deterministic use.
            return "Z";
      end case;
   end Persistent_Value_Image;

   function Persistent_Image (Expr : Expression) return Wide_Wide_String is
      R : Unbounded_Wide_Wide_String;
      procedure Emit (E : Expression) is
      begin
         if E.Node = null then
            Append (R, "L[Z]");
            return;
         end if;
         case E.Node.Kind is
            when Literal_Expr =>
               Append (R, "L[");
               Append (R, Persistent_Value_Image (E.Node.Literal_Value));
               Append (R, "]");
            when Column_Expr =>
               Append (R, "C[");
               Append (R, N_Image (E.Node.Column_Id));
               Append (R, "]");
            when Add_Expr | Subtract_Expr | Multiply_Expr | Divide_Expr |
                 Equal_Expr | Not_Equal_Expr | Less_Expr | Less_Or_Equal_Expr |
                 Greater_Expr | Greater_Or_Equal_Expr | And_Expr | Or_Expr =>
               Append (R, "B[");
               Append (R, N_Image (Expression_Kind'Pos (E.Node.Kind)));
               Append (R, ":");
               Emit ((Node => E.Node.Left));
               Append (R, ":");
               Emit ((Node => E.Node.Right));
               Append (R, "]");
            when Not_Expr | Is_Null_Expr | Is_Not_Null_Expr =>
               Append (R, "U[");
               Append (R, N_Image (Expression_Kind'Pos (E.Node.Kind)));
               Append (R, ":");
               Emit ((Node => E.Node.Operand));
               Append (R, "]");
            when Function_Expr =>
               Append (R, "F[");
               Append (R, N_Image (Deterministic_Function'Pos (E.Node.Func)));
               Append (R, ":");
               Append (R, N_Image (Natural (E.Node.Args.Length)));
               for A of E.Node.Args loop
                  Append (R, ":");
                  Emit (A);
               end loop;
               Append (R, "]");
            when Registered_Function_Expr =>
               Append (R, "R[");
               Append (R, Escape_Text (To_Wide_Wide_String (E.Node.Function_Name)));
               Append (R, ":");
               Append (R, N_Image (Natural (E.Node.Registered_Args.Length)));
               for A of E.Node.Registered_Args loop
                  Append (R, ":");
                  Emit (A);
               end loop;
               Append (R, "]");
         end case;
      end Emit;
   begin
      Emit (Expr);
      return To_Wide_Wide_String (R);
   end Persistent_Image;

   function From_Persistent_Image
     (Text : Wide_Wide_String;
      Expr : out Expression) return Database.Status.Result is
      Pos : Natural := Text'First;
      Last : constant Natural := Text'Last;

      function Need (Ch : Wide_Wide_Character) return Boolean is
      begin
         if Pos > Last or else Text (Pos) /= Ch then
            return False;
         end if;
         Pos := Pos + 1;
         return True;
      end Need;

      function Read_To (Stop : Wide_Wide_Character; Item : out Unbounded_Wide_Wide_String) return Boolean is
      begin
         Item := Null_Unbounded_Wide_Wide_String;
         while Pos <= Last loop
            if Text (Pos) = Stop then
               return True;
            elsif Text (Pos) = '\' then
               Pos := Pos + 1;
               if Pos > Last then
                  return False;
               end if;
               Append (Item, Text (Pos));
               Pos := Pos + 1;
            else
               Append (Item, Text (Pos));
               Pos := Pos + 1;
            end if;
         end loop;
         return False;
      end Read_To;

      function Read_Natural (N : out Natural; Stop : Wide_Wide_Character) return Boolean is
         S : Unbounded_Wide_Wide_String;
      begin
         if not Read_To (Stop, S) then
            return False;
         end if;
         N := Natural'Wide_Wide_Value (To_Wide_Wide_String (S));
         return True;
      exception
         when others => return False;
      end Read_Natural;

      function Read_Natural_Delimited
        (N : out Natural;
         Delim : out Wide_Wide_Character) return Boolean is
         S : Unbounded_Wide_Wide_String;
      begin
         S := Null_Unbounded_Wide_Wide_String;
         while Pos <= Last loop
            if Text (Pos) = ':' or else Text (Pos) = ']' then
               Delim := Text (Pos);
               N := Natural'Wide_Wide_Value (To_Wide_Wide_String (S));
               Pos := Pos + 1;
               return True;
            else
               Append (S, Text (Pos));
               Pos := Pos + 1;
            end if;
         end loop;
         return False;
      exception
         when others => return False;
      end Read_Natural_Delimited;

      function Parse_Value (Bdy : Wide_Wide_String; V : out Database.Values.Value) return Boolean is
      begin
         if Bdy'Length = 0 then
            return False;
         end if;
         case Bdy (Bdy'First) is
            when 'Z' => V := Database.Values.Null_Value;
            return True;
            when 'B' => V := Database.Values.From_Boolean (Bdy'Length >= 3 and then Bdy (Bdy'First + 2) = '1');
            return True;
            when 'I' => V := Database.Values.From_Integer (Integer'Wide_Wide_Value (Bdy (Bdy'First + 2 .. Bdy'Last)));
            return True;
            when 'L' => V := Database.Values.From_Long_Integer (Long_Long_Integer'Wide_Wide_Value (Bdy (Bdy'First
              + 2 .. Bdy'Last)));
            return True;
            when 'T' => V := Database.Values.From_Text (Bdy (Bdy'First + 2 .. Bdy'Last));
            return True;
            when 'E' => V := Database.Values.From_Enum (Bdy (Bdy'First + 2 .. Bdy'Last));
            return True;
            when 'A' => V := Database.Values.From_Array_Text (Bdy (Bdy'First + 2 .. Bdy'Last));
            return True;
            when others => return False;
         end case;
      exception
         when others => return False;
      end Parse_Value;

      function Parse (E : out Expression) return Boolean is
         Tag : Wide_Wide_Character;
         Num : Natural;
         S : Unbounded_Wide_Wide_String;
         L, R, A : Expression;
         Args : Expression_Vectors.Vector;
         V : Database.Values.Value;
      begin
         if Pos > Last then
            return False;
         end if;
         Tag := Text (Pos);
         Pos := Pos + 1;
         if not Need ('[') then
            return False;
         end if;
         case Tag is
            when 'L' =>
               if not Read_To (']', S) then
                  return False;
               end if;
               if not Need (']') then
                  return False;
               end if;
               if not Parse_Value (To_Wide_Wide_String (S), V) then
                  return False;
               end if;
               E := Literal (V);
               return True;
            when 'C' =>
               if not Read_Natural (Num, ']') then
                  return False;
               end if;
               if not Need (']') then
                  return False;
               end if;
               E := Column (Num);
               return True;
            when 'B' =>
               if not Read_Natural (Num, ':') then
                  return False;
               end if;
               if not Need (':') then
                  return False;
               end if;
               if Num > Expression_Kind'Pos (Expression_Kind'Last) then
                  return False;
               end if;
               if not Parse (L) then
                  return False;
               end if;
               if not Need (':') then
                  return False;
               end if;
               if not Parse (R) then
                  return False;
               end if;
               if not Need (']') then
                  return False;
               end if;
               E := Binary (Expression_Kind'Val (Num), L, R);
               return True;
            when 'U' =>
               if not Read_Natural (Num, ':') then
                  return False;
               end if;
               if not Need (':') then
                  return False;
               end if;
               if Num > Expression_Kind'Pos (Expression_Kind'Last) then
                  return False;
               end if;
               if not Parse (A) then
                  return False;
               end if;
               if not Need (']') then
                  return False;
               end if;
               E := Unary (Expression_Kind'Val (Num), A);
               return True;
            when 'F' =>
               if not Read_Natural (Num, ':') then
                  return False;
               end if;
               if not Need (':') then
                  return False;
               end if;
               if Num > Deterministic_Function'Pos (Deterministic_Function'Last) then
                  return False;
               end if;
               declare
                  Count : Natural;
                  Delim : Wide_Wide_Character;
               begin
                  if not Read_Natural_Delimited (Count, Delim) then
                     return False;
                  end if;
                  if Count = 0 then
                     if Delim /= ']' then
                        return False;
                     end if;
                  else
                     if Delim /= ':' then
                        return False;
                     end if;
                     for I in 1 .. Count loop
                        if not Parse (A) then
                           return False;
                        end if;
                        Args.Append (A);
                        if I < Count then
                           if not Need (':') then
                           return False;
                           end if;
                        end if;
                     end loop;
                     if not Need (']') then
                        return False;
                     end if;
                  end if;
               end;
               E := Function_Call (Deterministic_Function'Val (Num), Args);
               return True;
            when 'R' =>
               if not Read_To (':', S) then
                  return False;
               end if;
               if not Need (':') then
                  return False;
               end if;
               declare
                  Count : Natural;
                  Delim : Wide_Wide_Character;
               begin
                  if not Read_Natural_Delimited (Count, Delim) then
                     return False;
                  end if;
                  if Count = 0 then
                     if Delim /= ']' then
                        return False;
                     end if;
                  else
                     if Delim /= ':' then
                        return False;
                     end if;
                     for I in 1 .. Count loop
                        if not Parse (A) then
                           return False;
                        end if;
                        Args.Append (A);
                        if I < Count then
                           if not Need (':') then
                           return False;
                           end if;
                        end if;
                     end loop;
                     if not Need (']') then
                        return False;
                     end if;
                  end if;
               end;
               E := Registered_Function_Call (To_Wide_Wide_String (S), Args);
               return True;
            when others => return False;
         end case;
      end Parse;
   begin
      if not Parse (Expr) or else Pos <= Last then
         Expr := Literal (Database.Values.Null_Value);
         return Database.Status.Failure (Database.Status.Serialization_Error,
           "malformed persistent expression metadata");
      end if;
      return Database.Status.Success;
   exception
      when others =>
         Expr := Literal (Database.Values.Null_Value);
         return Database.Status.Failure (Database.Status.Serialization_Error,
           "malformed persistent expression metadata");
   end From_Persistent_Image;

end Database.Expressions;
