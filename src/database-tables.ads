--  Generic typed Ada table API using explicit mapping functions.
with Ada.Containers.Indefinite_Vectors;
with Database.Predicates;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Transactions;
with Database.Types;
with Database.Values;
with Database.Indexes;
with Database.Queries;
with Database.Storage.Table_Heap;
with Database.Expressions;

   --  Public nested package `Database.Tables`.
package Database.Tables is
   generic
      --  Public type `Row_Type`.
      type Row_Type is private;
      --  Public type `Key_Type`.
      type Key_Type is private;
      --  Converts a typed Ada row object into the untyped database row representation.
      --  @param Item Typed Ada row value supplied by the caller.
      --  @return Database row produced from the typed item.
      with function To_Row (Item : Row_Type) return Database.Rows.Row;
      --  Converts an untyped database row into the typed Ada row representation.
      --  @param Row Database row read from storage or query execution.
      --  @return Typed Ada row value produced from the database row.
      with function From_Row (Row : Database.Rows.Row) return Row_Type;
      --  Extracts the primary key from a typed Ada row value.
      --  @param Item Typed Ada row value supplied by the caller.
      --  @return Primary key value for the typed row.
      with function Key_Of (Item : Row_Type) return Key_Type;
      --  Converts a typed key into a database value suitable for indexes and predicates.
      --  @param Key Typed key value supplied by the caller.
      --  @return Database value representation of the key.
      with function Key_Value (Key : Key_Type) return Database.Values.Value;
   --  Public nested package `Typed`.
   package Typed is
      --  Public type `Cursor`.
      type Cursor is private;

      --  Public operation `Register`. See the package documentation for transaction, ownership, and error-result
      --  semantics.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @return Status result describing whether the operation succeeded.
      function Register
        (DB     : in out Database.Handle;
         Schema : in out Database.Schema.Table_Schema) return Database.Status.Result;
      --  Public operation `Register`. See the package documentation for transaction, ownership, and error-result
      --  semantics.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @return Status result describing whether the operation succeeded.
      function Register
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : in out Database.Schema.Table_Schema) return Database.Status.Result;
      --  Public operation `Create_Index`. See the package documentation for transaction, ownership, and error-result
      --  semantics.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Name logical name of the object.
      --  @param Column column argument supplied to the operation.
      --  @param Unique unique argument supplied to the operation.
      --  @return Status result describing whether the operation succeeded.
      function Create_Index
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema;
         Name   : Wide_Wide_String;
         Column : Natural;
         Unique : Boolean := False) return Database.Status.Result;

      --  Public operation `Rebuild_Index`. See the package documentation for transaction, ownership, and error-result
      --  semantics.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Index_Id index id argument supplied to the operation.
      --  @return Result produced by the function.
      function Rebuild_Index
        (Tx       : in out Database.Transactions.Transaction;
         DB       : in out Database.Handle;
         Schema   : Database.Schema.Table_Schema;
         Index_Id : Database.Indexes.Index_Id) return Database.Status.Result;

      --  Return create composite index for the supplied database state or arguments.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Name logical name of the object.
      --  @param Columns columns argument supplied to the operation.
      --  @param Unique unique argument supplied to the operation.
      --  @return Status result describing whether the operation succeeded.
      function Create_Composite_Index
        (Tx      : in out Database.Transactions.Transaction;
         DB      : in out Database.Handle;
         Schema  : Database.Schema.Table_Schema;
         Name    : Wide_Wide_String;
         Columns : Database.Indexes.Column_Id_Vectors.Vector;
         Unique  : Boolean := False) return Database.Status.Result;

      --  Return create partial index for the supplied database state or arguments.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Name logical name of the object.
      --  @param Column column argument supplied to the operation.
      --  @param Predicate predicate argument supplied to the operation.
      --  @param Unique unique argument supplied to the operation.
      --  @return Status result describing whether the operation succeeded.
      function Create_Partial_Index
        (Tx        : in out Database.Transactions.Transaction;
         DB        : in out Database.Handle;
         Schema    : Database.Schema.Table_Schema;
         Name      : Wide_Wide_String;
         Column    : Natural;
         Predicate : Database.Predicates.Predicate;
         Unique    : Boolean := False) return Database.Status.Result;

      --  Return create expression index for the supplied database state or arguments.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Name logical name of the object.
      --  @param Expression expression argument supplied to the operation.
      --  @param Key_Kind key kind argument supplied to the operation.
      --  @param Unique unique argument supplied to the operation.
      --  @return Status result describing whether the operation succeeded.
      function Create_Expression_Index
        (Tx         : in out Database.Transactions.Transaction;
         DB         : in out Database.Handle;
         Schema     : Database.Schema.Table_Schema;
         Name       : Wide_Wide_String;
         Expression : Database.Expressions.Expression;
         Key_Kind   : Database.Types.Value_Kind;
         Unique     : Boolean := False) return Database.Status.Result;

      --  Public operation `Insert`. See the package documentation for transaction, ownership, and error-result
      --  semantics.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Item item argument supplied to the operation.
      --  @return Status result describing whether the operation succeeded.
      function Insert
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema;
         Item   : Row_Type) return Database.Status.Result;
      --  Public operation `Find`. See the package documentation for transaction, ownership, and error-result semantics.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Key key value used to identify the row or object.
      --  @param Item item argument supplied to the operation.
      --  @return Requested value or optional value according to the package contract.
      function Find
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema;
         Key    : Key_Type;
         Item   : out Row_Type) return Database.Status.Result;
      --  Public operation `Update`. See the package documentation for transaction, ownership, and error-result
      --  semantics.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Item item argument supplied to the operation.
      --  @return Status result describing whether the operation succeeded.
      function Update
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema;
         Item   : Row_Type) return Database.Status.Result;
      --  Public operation `Delete`. See the package documentation for transaction, ownership, and error-result
      --  semantics.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Key key value used to identify the row or object.
      --  @return Status result describing whether the operation succeeded.
      function Delete
        (Tx     : in out Database.Transactions.Transaction;
         DB     : in out Database.Handle;
         Schema : Database.Schema.Table_Schema;
         Key    : Key_Type) return Database.Status.Result;
      --  Public operation `Scan`. See the package documentation for transaction, ownership, and error-result semantics.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Predicate predicate argument supplied to the operation.
      --  @param Cursor cursor argument supplied to the operation.
      --  @return Result produced by the function.
      function Scan
        (Tx        : in out Database.Transactions.Transaction;
         DB        : in out Database.Handle;
         Schema    : Database.Schema.Table_Schema;
         Predicate : Database.Predicates.Predicate;
         C : out Cursor) return Database.Status.Result;
      --  Public operation `Scan_Query`. See the package documentation for transaction, ownership, and error-result
      --  semantics.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Predicate predicate argument supplied to the operation.
      --  @param Query query argument supplied to the operation.
      --  @return Result produced by the function.
      function Scan_Query
        (Tx        : in out Database.Transactions.Transaction;
         DB        : in out Database.Handle;
         Schema    : Database.Schema.Table_Schema;
         Predicate : Database.Predicates.Predicate;
         Query     : out Database.Queries.Query) return Database.Status.Result;
      --  Public operation `Has_Element`. See the package documentation for transaction, ownership, and error-result
      --  semantics.
      --  @param C c argument supplied to the operation.
      --  @return True when the requested condition holds;
      --  otherwise False or an explicit validation status.
      function Has_Element (C : Cursor) return Boolean;
      --  Public operation `Element`. See the package documentation for transaction, ownership, and error-result
      --  semantics.
      --  @param C c argument supplied to the operation.
      --  @return Requested value or optional value according to the package contract.
      function Element (C : Cursor) return Row_Type;
      --  Public operation `Next`. See the package documentation for transaction, ownership, and error-result semantics.
      --  @param Tx transaction object that scopes the operation.
      --  @param DB database handle used by the operation.
      --  @param Schema schema metadata used for validation or registration.
      --  @param Predicate predicate argument supplied to the operation.
      --  @param Cursor cursor argument supplied to the operation.
      --  @return Result produced by the function.
      function Next
        (Tx        : in out Database.Transactions.Transaction;
         DB        : in out Database.Handle;
         Schema    : Database.Schema.Table_Schema;
         Predicate : Database.Predicates.Predicate;
         C : in out Cursor) return Database.Status.Result;
   private
      --  Public nested package `Row_Vectors`.
      package Row_Vectors is new Ada.Containers.Indefinite_Vectors (Natural, Row_Type);
      --  Public type `Cursor`.
      type Cursor is record
         In_Memory_Index : Natural := 0;
         In_Memory_Rows  : Row_Vectors.Vector;
         Heap            : Database.Storage.Table_Heap.Heap_Cursor;
         Current         : Row_Type;
         Has_Current     : Boolean := False;
         Uses_Materialized : Boolean := False;
         Owner_Tx_Id     : Natural := 0;
         Owner_Snapshot  : Natural := 0;
      end record;
   end Typed;
end Database.Tables;
