package body Database.Cursors is
   function Is_Valid (State : Cursor_State) return Boolean is
   begin
      return State = Valid;
   end Is_Valid;

   function To_Result (State : Cursor_State) return Database.Status.Result is
   begin
      case State is
         when Valid =>
            return Database.Status.Success;
         when No_Element =>
            return Database.Status.Failure (Database.Status.Not_Found, "cursor has no current element");
         when Wrong_Transaction =>
            return Database.Status.Failure (Database.Status.Transaction_Error,
              "cursor used with a different transaction");
         when Expired_Snapshot =>
            return Database.Status.Failure (Database.Status.Transaction_Conflict,
              "cursor snapshot is no longer current");
         when Closed_Transaction =>
            return Database.Status.Failure (Database.Status.Transaction_Error, "cursor transaction is not active");
      end case;
   end To_Result;

   function Validate_Owner
     (Tx             : in out Database.Transactions.Transaction;
      Owner_Tx_Id    : Natural;
      Owner_Snapshot : Natural;
      Has_Element    : Boolean := True) return Cursor_State is
      DB : access Database.Handle;
   begin
      if not Database.Transactions.Is_Active (Tx) then
         return Closed_Transaction;
      end if;
      if Database.Transactions.Id (Tx) /= Owner_Tx_Id then
         return Wrong_Transaction;
      end if;
      DB := Database.Transactions.Owning_Database (Tx);
      if DB /= null and then Database.Commit_Version (DB.all) /= Owner_Snapshot then
         return Expired_Snapshot;
      end if;
      if not Has_Element then
         return No_Element;
      end if;
      return Valid;
   end Validate_Owner;
end Database.Cursors;
