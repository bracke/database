with Database.Aggregates;
with Database.Ordering;
with Database.Predicates;
with Database.Queries;
with Database.Rows;
with Database.Status;
with Database.Values;

procedure Main is
   Q, Adults : Database.Queries.Query;
   Aggs : Database.Aggregates.Aggregate_Vectors.Vector;
   R, Aggregate_Row : Database.Rows.Row;
   S : Database.Status.Result;
begin
   Database.Rows.Append (R, Database.Values.From_Integer (1));
   Database.Rows.Append (R, Database.Values.From_Text ("Ada"));
   Database.Rows.Append (R, Database.Values.From_Integer (42));
   Database.Queries.Append (Q, R);

   R.Values.Clear;
   Database.Rows.Append (R, Database.Values.From_Integer (2));
   Database.Rows.Append (R, Database.Values.From_Text ("Grace"));
   Database.Rows.Append (R, Database.Values.From_Integer (35));
   Database.Queries.Append (Q, R);

   Adults := Database.Queries.Order_By
     (Database.Queries.Filter
        (Q, Database.Predicates.Column_Not_Equals (2, Database.Values.From_Integer (0))),
      1,
      Database.Ordering.Ascending);

   Aggs.Append (Database.Aggregates.Count);
   S := Database.Queries.Aggregate (Adults, Aggs, Aggregate_Row);
   pragma Assert (Database.Status.Is_Ok (S), "aggregate query failed");
   pragma Assert (Database.Rows.Get (Aggregate_Row, 0).Int = 2, "aggregate count mismatch");
end Main;
