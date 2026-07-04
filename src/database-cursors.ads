--  Cursor lifetime and validation helpers shared by cursor-producing APIs.
--
--  Cursor values returned by table scans are owned by the transaction that
--  created them.  A cursor is valid only while that transaction remains active
--  and while the database commit version still matches the cursor snapshot.
--  This package intentionally does not expose table cursor internals;
--  it
--  centralizes the public terminology used by Database.Tables and the user
--  documentation.
with Database.Status;
with Database.Transactions;

--  Public specification for this database subsystem.
package Database.Cursors is
   --  High-level state reported by APIs that validate cursor ownership.
   type Cursor_State is
     (Valid,
      No_Element,
      Wrong_Transaction,
      Expired_Snapshot,
      Closed_Transaction);

   --  Return True when State permits reading the current element.
   --  @param State state argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Is_Valid (State : Cursor_State) return Boolean;

   --  Convert a cursor state to a structured status result.
   --  @param State state argument supplied to the operation.
   --  @return Result produced by the function.
   function To_Result (State : Cursor_State) return Database.Status.Result;

   --  Validate a captured transaction id and snapshot against the current
   --  transaction.  Cursor-producing packages use the same rules: the owning
   --  transaction must be active, must have the same id, and must still be at
   --  the snapshot visible when the cursor was created.
   --  @param Tx transaction object that scopes the operation.
   --  @param Owner_Tx_Id owner tx id argument supplied to the operation.
   --  @param Owner_Snapshot owner snapshot argument supplied to the operation.
   --  @param Has_Element has element argument supplied to the operation.
   --  @return True when the requested condition holds;
   --  otherwise False or an explicit validation status.
   function Validate_Owner
     (Tx             : in out Database.Transactions.Transaction;
      Owner_Tx_Id    : Natural;
      Owner_Snapshot : Natural;
      Has_Element    : Boolean := True) return Cursor_State;
end Database.Cursors;
