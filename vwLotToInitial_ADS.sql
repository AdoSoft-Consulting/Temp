create   view vwLotToInitial_ADS
as
/* 
   ===============================================================
     VIEW: vwLotToInitial_ADS
     SCOP:
       - traduce direct structura LotUsage_ADS într-o formă lizibilă
       - normalizează cantitățile consumate / produse
       - repară cazurile speciale (lot final = lot inițial)
       - tratează corect și transformările intermediare

     REGULI:
       - Dacă LotFinal = LotInitial → lot final vândabil
            ConsumedQty = ProducedQtty
            TotalConsumedQtty = TotalProducedQtty
            ProportionPer1Final = 1
            PctOfFinalLot = 1

       - Altfel (lot inițial sau intermediar)
            ConsumedQty = InitialConsumedQty
            TotalConsumedQtty = SUM(initialConsumedQty)
   ===============================================================
*/

with x as (
    select
        u.FinalLot,
        u.InitialLot,

        u.Depth,

        -- consum real la nivel de lot inițial
        InitialConsumedQty = u.InitialConsumedQty,

        -- producția reală atribuită fiecărei legături
        ProducedQtty       = u.FinalObtainedQty,

        u.ProportionPer1Final,   -- factor tehnic
        u.PctOfFinalLot,         -- procent din lotul final

        -- totaluri pe final
        TotalProducedQtty = sum(u.FinalObtainedQty) over (partition by u.FinalLot),
        TotalConsumedQtty = sum(u.InitialConsumedQty) over (partition by u.FinalLot)

    from LotUsage_ADS u with (nolock)
)

select
    FinalLot      = x.FinalLot,
    InitialLot    = x.InitialLot,
    Depth         = x.Depth,

    /* ------------------------------------------------------
       ConsumedQty:
         - lot final → consumul = producția sa
         - alt lot   → consumul real din Usage
       ------------------------------------------------------ */
    ConsumedQty =
        round(
            case 
                when x.FinalLot = x.InitialLot then x.ProducedQtty
                else x.InitialConsumedQty
            end, 6
        ),

    /* ------------------------------------------------------
       TotalConsumedQtty:
         - lot final → consum total = producția totală
         - alt lot   → sumă consumuri inițiale
       ------------------------------------------------------ */
    TotalConsumedQtty =
        round(
            case
                when x.FinalLot = x.InitialLot then x.TotalProducedQtty
                else x.TotalConsumedQtty
            end, 6
        ),

    /* ------------------------------------------------------
       Producția atribuită pe filieră
       ------------------------------------------------------ */
    ProducedQtty      = round(x.ProducedQtty, 6),
    TotalProducedQtty = round(x.TotalProducedQtty, 6),

    /* ------------------------------------------------------
       ProportionPer1Final:
         - lot final → 1
         - alt lot   → factor tehnic real
       ------------------------------------------------------ */
    ProportionPer1Final =
        round(
            case 
                when x.FinalLot = x.InitialLot then 1
                else x.ProportionPer1Final
            end, 6
        ),

    /* ------------------------------------------------------
       PctOfFinalLot:
         - lot final → 1
         - alt lot   → pondere reală în lotul final
       ------------------------------------------------------ */
    PctOfFinalLot =
        round(
            case
                when x.FinalLot = x.InitialLot then 1
                else x.PctOfFinalLot
            end, 6
        )

from x;

