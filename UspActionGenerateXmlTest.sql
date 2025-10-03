create or alter procedure Saft.UspActionGenerateXmlTest
	(@CompanyId int, @Language varchar(2)='RO', @RepVersionId int, @RepTypeId int, @RepTypeExtId int, @StartDate date, @EndDate date, 
	@UserId int, @SessionId uniqueidentifier=null, @vMessage varchar(2000)=null output)
as
begin
	set nocount on
	set ansi_warnings off

SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

	Init:
	begin
		declare @ActionId int, @StepActionId int, @CalendarId int, @DeBug int, @TimeStamp datetime, @SoftwareVersion varchar(100),
			@AuditFile varchar(max), @XmlNoSchema xml, @xstate int, @StatementId int, @ReportingType varchar(4), @RepDescription varchar(255), 
			@FakeAccountId int, @SelfPartnerId int, @SelfSaftPartnerId varchar(35), @SelfCIF varchar(100),
			@YearStartDate date, @YearEndDate date, @FirstDate date,
			@Id_Currency int, @Id_DeprecType int, @RON_Currency int, 
			@SegmentIndex int, @TotalSegmentsInsequence int, @CountSection bigint, @CountGL bigint, @GroupGL int, 
			@Flag int, @Testing bit, @AccSystemId int, @AccSystemCode varchar(18),
			@WarningMessage varchar(2000), @ErrorMessage varchar(2000), @MessageRO varchar(2000), @MessageEN varchar(2000), @InfoXml xml,
			@SourceDocuments int=1,
			@GeneralLedgerAccounts int=0, @Customers int=0, @Suppliers int=0, @TaxTable int=0, @UOMTable int=0, @AnalysisTypeTable int=0,
			@MovementTypeTable int=0, @Products int=0, @PhysicalStock int=0, @Owners int=0, @Assets int=0,
			@GeneralLedgerEntries int=0,
			@PurchaseInvoice int=0, @SalesInvoice int=0, @Payment int=0, @MovementOfGoods int=0, @AssetTransactions int=0,
			@LastDataGeneralLedgerProcess datetime, @LastDataAccountingJournalChecks datetime, @RefKeyId int, @TaxVersionVAT int

		declare @XmlD406 xml ([D406 2.4.9]), @XmlD406T xml ([D406T 2.4.8])
		
		set @DeBug=0
		set @vMessage=''
		set @Language=upper(isnull(@Language,'RO'))
		set @StatementId=1
		set @TimeStamp=getdate()
		set @GroupGL=0
		set @CountSection=0
		set @ErrorMessage=''
		set @WarningMessage=''
		set @MessageRO=''
		set @MessageEN=''
		set @Flag=0
		set @SegmentIndex=1
		set @TotalSegmentsInsequence=1

		select @SoftwareVersion=ExVersion
		from Entity (nolock)
		where EntityId=8

		set @StartDate=dateadd(dd,1,eomonth(@StartDate,-1))
		set @EndDate=eomonth(@EndDate)

		select @FirstDate=x.StartDate, 
			@AccSystemId=AccSystemId
		from Saft.CompanyXStatement x (nolock)
		where x.CompanyId=@CompanyId
			and x.StatementId=1
		
		select @CalendarId=cp.CalendarId
		from CalendarPeriod cp (nolock)
		where eomonth(cp.StartDate)=eomonth(@StartDate)

		select @YearStartDate=min(cp.StartDate),
			@YearEndDate=max(cp.EndDate)
		from CalendarPeriod cp (nolock)
		where cp.CalendarId=@CalendarId

		select @AccSystemCode=AccSystemCode
		from Saft.AccountSystem (nolock)
		where AccSystemId=@AccSystemId

		select @TaxVersionVAT=iif(@EndDate<='20250731',1,2)

		if isnull(@vMessage,'')=''
		and @SessionId is null
		set @vMessage='Sesiune neidentificata'

		if isnull(@vMessage,'')=''
		and eomonth(@StartDate)>eomonth(@EndDate)
		set @vMessage='Perioada selectata este incorecta'
		
		if isnull(@vMessage,'')=''
		and @FirstDate is null
		set @vMessage='Luna inceput depunere SAF-T este necompletata pentru compania curenta'

		if isnull(@vMessage,'')=''
		and @StartDate<@FirstDate
		set @vMessage='Luna inceput depunere SAF-T pentru compania curenta este ulterioara datei de inceput selectate'
		
		if isnull(@vMessage,'')=''
		and @EndDate>@YearEndDate
		set @vMessage='Daca de inceput si data de sfarsit nu se afla in acelasi an fiscal'

		if isnull(@vMessage,'')=''
		and ((@RepTypeExtId=1 and eomonth(@StartDate)<>eomonth(@EndDate))
			or (@RepTypeExtId=3 and (@StartDate<>@YearStartDate or @EndDate<>@YearEndDate))
			or 1=2)
		set @vMessage='Perioada selectata este incorecta'

		if isnull(@vMessage,'')=''
		and @AccSystemCode is null
		set @vMessage='Sistem contabil neidentificat'

		if isnull(@vMessage,'')=''
		begin
			select @LastDataGeneralLedgerProcess=max(x.EndTime)
			from Saft.UserActionLogHistory x (nolock) 
			where x.CompanyId=@CompanyId 
				and x.StartDate=@StartDate
				and x.EndDate=@EndDate
				and x.ActionId=8 /*Jurnale Contabile*/

			select @LastDataAccountingJournalChecks=max(x.EndTime)
			from Saft.UserActionLogHistory x (nolock) 
			where x.CompanyId=@CompanyId 
				and x.StartDate=@StartDate
				and x.EndDate=@EndDate
				and x.ActionId=9 /*Verificari Jurnale Contabile*/ 

			if @LastDataGeneralLedgerProcess>isnull(@LastDataAccountingJournalChecks,'19000101')
			set @vMessage='Procesare Date: Actiunea ''Verificari Jurnale Contabile'' nu a fost rulata ulterior actiunii ''Jurnale Contabile''!'
		end

		if isnull(@vMessage,'')<>'' goto EndOfProc			

		select top 1 @DeBug=ProcessId
		from dbo.ContextInfo (nolock)
		where SpId=@@spid
			and SessionId=@SessionId	

		select @ReportingType=RepTypeExtCode
		from Saft.ReportTypeExt x (nolock)
		where x.RepTypeExtId=@RepTypeExtId

		select @Testing=x.Testing
		from Saft.CompanyXStatement x
		where x.CompanyId=@CompanyId
			and x.StatementId=@StatementId

		if @Testing is null
		begin
			set @vMessage='Declaratia D406 nu este implementata in societatea curenta'
			goto EndOfProc
		end

		select @ActionId=case when @RepTypeId=1 and @RepTypeExtId=1 then 11
								when @RepTypeId=1 and @RepTypeExtId=2 then 12
								when @RepTypeId=2 then 13
								when @RepTypeId=3 then 14
								when @RepTypeId=4 then 15
								when @RepTypeId=5 then 18
								end

		select @Id_Currency		=DictionaryId from dbo.Dictionary (nolock) where DictionaryName='Currency'
		select @Id_DeprecType	=DictionaryId from dbo.Dictionary (nolock) where DictionaryCode='AMTYPE'
		select @RON_Currency=ItemId from dbo.DictionaryItem (nolock) where DictionaryId=@Id_Currency and ItemCode='RON'

		insert into Saft.UserActionLogHistory 
			(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, SessionId, SpId)
		select @CompanyId, @ActionId, @StartDate, @EndDate, @UserId, @TimeStamp, @SessionId, @@SpId

		select top 1 @FakeAccountId=AccountId 
		from Saft.vwAccountChart a
		where a.AccSystemId=@AccSystemId

		select top 1 @SelfPartnerId=p.PartnerId, 
			@SelfCIF=TaxRegistrationNumber
		from dbo.Company c (nolock) 
		join dbo.Partner p (nolock) on c.ImportedCompanyId=p.ImportedPartnerId
		where CompanyId=@CompanyId

		if isnull(@vMessage,'')<>''    goto EndOfProc

		if @UserId=1 and @Testing=1
		begin
			select @SelfCIF=isnull(nullif([Value],''),@SelfCIF)
			from ConfigurationItem (nolock)
			where [Type]='Saft' 
				and [Name]='Testing_CIF'
		end
		
		set @RepDescription=iif(@Testing=0,'D406','D406T')+'_'+@SelfCIF+'_'
			+case when @RepTypeExtId=1
						then @ReportingType+'_'+convert(nvarchar(4),year(@StartDate))+'_'+convert(nvarchar(2),month(@StartDate))
					when @RepTypeExtId=2
						then convert(nvarchar(4),year(@StartDate))+'_'+@ReportingType+''+convert(nvarchar(4),datepart(quarter,@StartDate))
					when @RepTypeExtId=3
						then @ReportingType+'_'+convert(nvarchar(4),year(@StartDate))
					when @RepTypeExtId=4
						then @ReportingType+' ['+convert(nvarchar(20),@StartDate,6)+'-'+convert(nvarchar(20),@EndDate,6)+']'
					when @RepTypeExtId=7
						then @ReportingType+'_'+convert(nvarchar(4),year(@StartDate))+'_'+convert(nvarchar(2),month(@StartDate))
					else
						@ReportingType+' ['+convert(nvarchar(20),@StartDate,6)+'-'+convert(nvarchar(20),@EndDate,6)+']'
					end

		if @TotalSegmentsInsequence>1
		set @RepDescription=@RepDescription+'_['+convert(varchar,@SegmentIndex)+'.'+convert(varchar,@TotalSegmentsInsequence)+']'

		drop table if exists #ReportStructure
		drop table if exists #Company
		drop table if exists #GeneralLedgerAccounts
		drop table if exists #PartnerAccount
		drop table if exists #TaxTable
		drop table if exists #xTaxTable
		drop table if exists #AnalysisTypeTable
		drop table if exists #MovementTypeTable
		drop table if exists #Products
		drop table if exists #PhysicalStock
		drop table if exists #Owners
		drop table if exists #Assets
		drop table if exists #MeasuringUnit
		drop table if exists #GeneralLedgerEntries
		drop table if exists #xGeneralLedgerEntries
		drop table if exists #Invoice
		drop table if exists #Payment
		drop table if exists #AssetTransaction
		drop table if exists #InvoiceAccount
		drop table if exists #InvoiceTax
		drop table if exists #PaymentTax
		drop table if exists #Partners
		drop table if exists #ActionLogError

		create table #GeneralLedgerAccounts
			(AccountID varchar(70), AccountDescription varchar(255), StandardAccountID varchar(35), AccountType varchar(18), 
			OpeningDebitBalanceIni numeric(18,2), OpeningCreditBalanceIni numeric(18,2), 
			OpeningDebitBalance numeric(18,2), OpeningCreditBalance numeric(18,2), 
			TurnOverDebit numeric(18,2), TurnOverCredit numeric(18,2), 
			ClosingDebitBalance numeric(18,2), ClosingCreditBalance numeric(18,2))

		create table #PartnerAccount
			(xType varchar(255), PartnerId int, SaftPartnerId varchar(35), 
			AccountID varchar(70), AccountType varchar(100), IsCustomer bit, IsSupplier bit, 
			TurnOverDebit numeric(18,2), TurnOverCredit numeric(18,2),
			OpeningDebitBalanceIni numeric(18,2), OpeningCreditBalanceIni numeric(18,2), 
			OpeningDebitBalance numeric(18,2), OpeningCreditBalance numeric(18,2), 
			ClosingDebitBalance numeric(18,2), ClosingCreditBalance numeric(18,2))

		create table #Products
			(ItemId int, ProductCode varchar(70), Description varchar(255), ProductCommodityCode varchar(8), 
			UOMBase varchar(9), UOMStandard varchar(9), UOMToUOMBaseConversionFactor money)

		create table #xTaxTable
			(TaxCode varchar(9))

		create table #TaxTable
			(TaxType varchar(9), TaxTypeDescription varchar(255), TaxCode varchar(9), 
			TaxPercentage numeric(18,4), Amount numeric(18,2), CurrencyCode varchar(3), CurrencyAmount numeric(18,2), BaseRate numeric(18,4), Country varchar(2))
			
		create table #AnalysisTypeTable
			(AnalysisType varchar(9), AnalysisTypeDescription varchar(255), AnalysisID varchar(35), AnalysisIDDescription varchar(255))
	
		create table #PhysicalStock
			(ItemId int, WarehouseID varchar(35), ProductCode varchar(70), ProductType varchar(18), StockAccountCommodityCode varchar(8),
			OwnerID varchar(35), UOMPhysicalStock varchar(9), UOMToUOMBaseConversionFactor numeric(18,4), UnitPrice money, 
			OpeningStockQuantity numeric(22,6), OpeningStockValue numeric(18,2), ClosingStockQuantity numeric(22,6), ClosingStockValue numeric(18,2))

		create table #Owners
			(PartnerId int, AccountId int, SaftAccountCode varchar(35))

		create table #MeasuringUnit
			(MeasuringUnitId int, SaftCode varchar(255), SaftName varchar(255))

		create table #MovementTypeTable
			(MovementCode varchar(9), MovementName varchar(255))

		create table #GeneralLedgerEntries
			(CompanyId int, CalendarPeriodId int, xType varchar(1), SaftAccountCode varchar(35), 
			PartnerId int, TransactionDate date, SystemEntryDate date, Description varchar(255), 
			AccBillKeyId bigint, PostingKeyId bigint, DocumentKeyId bigint, DocumentDetailKeyId bigint, 
			LineDescription varchar(255), CurrencyAmount numeric(18,2), Amount numeric(18,2), 
			CurrencyCode varchar(3), ExchangeRate numeric(18,4), TaxType varchar(3), TaxCode varchar(8), 
			TaxPercentage numeric(18,2), TaxBase numeric(18,2), TaxAmount numeric(18,2), 
			TaxBaseDescription varchar(255), TaxCurrencyCode varchar(3), TaxInv bit, DocTypeId int,
			IsTaxVAT int, RowD300 varchar(255), InvoiceTypeCode varchar(3), VATId int)

		create table #xGeneralLedgerEntries
			(CompanyId int, CalendarPeriodId int, xType varchar(1), SaftAccountCode varchar(35), 
			PartnerId int, TransactionDate date, SystemEntryDate date, Description varchar(255), 
			AccBillKeyId bigint, PostingKeyId bigint, DocumentKeyId bigint, DocumentDetailKeyId bigint, 
			LineDescription varchar(255), CurrencyAmount numeric(18,2), Amount numeric(18,2), 
			CurrencyCode varchar(3), ExchangeRate numeric(18,4), TaxType varchar(3), TaxCode varchar(8), 
			TaxPercentage numeric(18,2), TaxBase numeric(18,2), TaxAmount numeric(18,2), 
			TaxBaseDescription varchar(255), TaxCurrencyCode varchar(3), SaftPartnerId varchar(35))

		create table #Invoice
			(DocumentTypeId int, DocumentKeyId bigint, DocumentDetailKeyId bigint, PartnerId int, PartnerAddressId int, DeliveryAddressId int, 
			DocumentDate date, DocumentNumber varchar(25), ItemId int, CurrencyId int, MeasuringUnitId int,			
			Quantity numeric(22,6), UnitPrice numeric(18,2), 
			Amount numeric(18,2), CurrencyAmount numeric(18,2), ExchangeRate numeric(18,4), TaxAmount numeric(18,4),
			ProductCode varchar(70), ProductDescription varchar(255), Description varchar(255), TaxPointDate date, 
			CurrencyCode varchar(3), GoodsServicesID varchar(2), AccountId_H int, AccountId_D int,
			DebitCreditIndicator varchar(9), InvoiceTypeCode varchar(3))

		create table #Payment
			(DocumentTypeId int, DocumentKeyId bigint, DocumentDetailKeyId bigint, PartnerId int, 
			DocumentNumber varchar(25), DocumentDate date, TaxPointDate date, 
			PaymentMethod varchar(18), PaymentMechanism varchar(9), PaymentRefNo varchar(35), Description varchar(255), 
			AccountID int, CustomerPartnerId int, SupplierPartnerId int, DebitCreditIndicator varchar(9), 
			Amount numeric(18,2), CurrencyAmount numeric(18,2), ExchangeRate numeric(18,4), 
			RefDocumentTypeId int, RefDocumentKeyId bigint, RefDocumentNumber varchar(25), 
			CurrencyCode varchar(3), CurrencyId int, HashKey_H varbinary(32), HashKey_D varbinary(32))

		create table #InvoiceTax
			(DocumentKeyId bigint, DocumentDetailKeyId bigint, 
			TaxType varchar(3), TaxCode varchar(6), TaxCurrencyCode varchar(3), TaxBase numeric(18,2), TaxAmount numeric(18,2))

		create table #PaymentTax
			(HashKey_D varbinary(32), 
			TaxType varchar(3), TaxCode varchar(6), TaxCurrencyCode varchar(3), TaxBase numeric(18,2), TaxAmount numeric(18,2))

		create table #Partners
			(PartnerId int, SaftPartnerId varchar(35), PartnerName varchar(70),
			City varchar(35), District varchar(35), Country varchar(35))

		create table #Assets
			(AssetCardId int, AccountId int, SaftAccountCode varchar(35), Description varchar(255), DateOfAcquisition date, StartUpDate date, 
			ValuationClass varchar(18),
			AcquisitionAndProductionCostsBegin numeric(18,2),
			AcquisitionAndProductionCostsEnd numeric(18,2),
			InvestmentSupport numeric(18,2),
			AssetLifeYear numeric(18,2),
			AssetLifeMonth numeric(18,2),
			AssetAddition numeric(18,2),
			Transfers numeric(18,2),
			AssetDisposal numeric(18,2),
			BookValueBegin numeric(18,2),
			DepreciationMethod varchar(35), 
			DepreciationPercentage numeric(18,2),
			DepreciationForPeriod numeric(18,2),
			AppreciationForPeriod numeric(18,2),
			AccumulatedDepreciation numeric(18,2),
			BookValueEnd numeric(18,2),
			ExtraordinaryDepreciationMethod varchar(35), 
			ExtraordinaryDepreciationAmountForPeriod numeric(18,2))

		create table #AssetTransaction
			(AssetCardId int, JournalId bigint, TransactionId bigint, 
			TransactionCode varchar(3), Description varchar(255), TransactionDate date, 
			AcquisitionAndProductionCosts numeric(18,2), BookValue numeric(18,2), Amount numeric(18,2))

		create table #ActionLogError
			(ActionId int, Flag int, ErrorName varchar(255), ErrorInfo varchar(2000))

		declare @TempErrorInfo table 
			(ErrorInfo varchar(2000))

	end
	
	Prep:
	begin

		select rs.StrType, rs.StrCode, rs.ParentStrCode, rs.DescriptionRO, rs.DescriptionEN, rs.ActionId
		from Saft.ReportStructure rs (nolock)
		join Saft.ReportTypeXStructure rts (nolock) on rs.RepVersionId=rts.RepVersionId and rs.StrCode=rts.StrCode
		where rs.RepVersionId=@RepVersionId 
			and rts.RepTypeId=@RepTypeId

		select rs.StrType, rs.StrCode, rs.ParentStrCode, rs.DescriptionRO, rs.DescriptionEN, rs.ActionId
		into #ReportStructure
		from Saft.ReportStructure rs (nolock)
		join Saft.ReportTypeXStructure rts (nolock) on rs.RepVersionId=rts.RepVersionId and rs.StrCode=rts.StrCode
		where rs.RepVersionId=@RepVersionId 
			and rts.RepTypeId=@RepTypeId

		select p.TaxRegistrationNumber, p.SaftPartnerId, p.PartnerId,
			PartnerName=left(p.PartnerName,70), p.City, p.District, p.Country, p.Street, LocalNumber=isnull(nullif(p.LocalNumber,''),'1'), p.AdditionalAddressDetail,			
			p.ContactPersonFirstName, p.ContactPersonLastName, p.ContactPerson, p.Telephone--, ba.IBAN
		into #Company
		from dbo.Company c (nolock)
		join Saft.vwPartner p on c.ImportedCompanyId=p.ImportedPartnerId
		where c.CompanyId=@CompanyId

		select @SelfSaftPartnerId=SaftPartnerId
		from #Company c
		
		GeneralLedgerAccounts:
		if exists (select 1 from #ReportStructure where StrCode='2.1')
		begin
			set @GeneralLedgerAccounts=1
			set @StepActionId=23 /*MasterFiles - GeneralLedgerAccounts*/
			set @TimeStamp=getdate()

			insert into #GeneralLedgerAccounts
				(AccountID, AccountDescription, StandardAccountID, AccountType, 
				OpeningDebitBalanceIni, OpeningCreditBalanceIni, TurnOverDebit, TurnOverCredit)
			select AccountID=ac.SaftAccountCode,
				AccountDescription=iif(@Language='RO',ac.SaftAccountNameRO,ac.SaftAccountNameEN), 
				StandardAccountID=left(ac.AccountSymbol,35),
				AccountType=ac.AccountType,
				OpeningDebitBalanceIni=(a.OpeningDebitBalance), 
				OpeningCreditBalanceIni=(a.OpeningCreditBalance), 
				TurnOverDebit=(a.TurnOverDebit), 
				TurnOverCredit=(a.TurnOverCredit)
			from (
				select a.AccountId,
					OpeningDebitBalance=sum(iif(eomonth(cp.StartDate)=eomonth(@StartDate),a.EqOpeningBalanceDebit,0)),
					OpeningCreditBalance=sum(iif(eomonth(cp.StartDate)=eomonth(@StartDate),a.EqOpeningBalanceCredit,0)),
					TurnOverDebit=sum(a.EqTurnOverDebit),
					TurnOverCredit=sum(a.EqTurnOverCredit)
				from Saft.AccountTurnOver a (nolock)
				join dbo.CompanyLocation cl (nolock) on cl.LocationId=a.LocationId
				join dbo.CalendarPeriod cp (nolock) on a.CalendarPeriodId=cp.CalendarPeriodId
				where cl.CompanyId=@CompanyId
					and cp.StartDate>=@StartDate
					and cp.EndDate<=@EndDate
				group by a.AccountId) a
			join Saft.vwAccountChart ac on a.AccountId=ac.AccountId
			where left(ac.SaftAccountCode,1) not in ('8','9')
				and ac.AccSystemId=@AccSystemId

			update a
			set OpeningDebitBalance=case when a.AccountType='Activ' or (a.AccountType='Bifunctional' and a.OpeningDebitBalanceIni>=a.OpeningCreditBalanceIni) 
											then a.OpeningDebitBalanceIni-a.OpeningCreditBalanceIni
											else null end,
				OpeningCreditBalance=case when a.AccountType='Pasiv' or (a.AccountType='Bifunctional' and a.OpeningDebitBalanceIni<a.OpeningCreditBalanceIni) 
											then a.OpeningCreditBalanceIni-a.OpeningDebitBalanceIni
											else null end
			from #GeneralLedgerAccounts a

			update a
			set ClosingDebitBalance=case when a.AccountType='Activ' then isnull(a.OpeningDebitBalance,0)+a.TurnOverDebit-a.TurnOverCredit
										when a.AccountType='Bifunctional' and isnull(a.OpeningDebitBalance,0)-isnull(a.OpeningCreditBalance,0)+a.TurnOverDebit-a.TurnOverCredit>0
											then isnull(a.OpeningDebitBalance,0)-isnull(a.OpeningCreditBalance,0)+a.TurnOverDebit-a.TurnOverCredit
										else null end,
				ClosingCreditBalance=case when a.AccountType='Pasiv' then isnull(a.OpeningCreditBalance,0)+a.TurnOverCredit-a.TurnOverDebit
										when a.AccountType='Bifunctional' and isnull(a.OpeningCreditBalance,0)-isnull(a.OpeningDebitBalance,0)-a.TurnOverDebit+a.TurnOverCredit>0
											then isnull(a.OpeningCreditBalance,0)-isnull(a.OpeningDebitBalance,0)-a.TurnOverDebit+a.TurnOverCredit
										else null end 
			from #GeneralLedgerAccounts a

			update a
			set OpeningDebitBalance=0
			from #GeneralLedgerAccounts a
			where a.OpeningDebitBalance is null and a.OpeningCreditBalance is null

			update a
			set ClosingDebitBalance=0
			from #GeneralLedgerAccounts a
			where a.ClosingDebitBalance is null and a.ClosingCreditBalance is null

			select @CountSection=count(1) from #GeneralLedgerAccounts

			if @CountSection=0
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Registrul Jurnal'
				set @MessageEN='No records in the GeneralLedgerAccounts section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end

			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, EndTime=getdate(), @SessionId, @@SpId
				
			if @DeBug=97 select '#GeneralLedgerAccounts', NrInreg=count(1) from #GeneralLedgerAccounts

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: GeneralLedgerAccounts='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end

		end

		Customers:
		if exists (select 1 from #ReportStructure where StrCode='2.3')
		begin
			set @Customers=1
			set @Suppliers=1

			set @StepActionId=28 /*MasterFiles - Partners*/
			set @TimeStamp=getdate()

			insert into #PartnerAccount
				(xType, PartnerId, AccountID, AccountType, 
				TurnOverDebit, TurnOverCredit, OpeningDebitBalanceIni, OpeningCreditBalanceIni)
			select xType=case when left(ac.SaftAccountCode,2)='40' then 'Furnizori' when left(ac.SaftAccountCode,2)='41' then 'Clienti' else '' end, 
				PartnerId=a.PartnerId,
				AccountID=ac.SaftAccountCode,
				AccountType=ac.AccountType,
				TurnOverDebit=sum(a.EqTurnOverDebit),
				TurnOverCredit=sum(a.EqTurnOverCredit),
				OpeningDebitBalanceIni=sum(a.EqOpeningBalanceDebit),
				OpeningCreditBalanceIni=sum(a.EqOpeningBalanceCredit)
			from Saft.PartnerAccountTurnOver a (nolock)
			join dbo.CompanyLocation cl (nolock) on cl.LocationId=a.LocationId
			join dbo.CalendarPeriod cp (nolock) on a.CalendarPeriodId=cp.CalendarPeriodId
			join Saft.vwAccountChart ac on a.AccountId=ac.AccountId
			where cl.CompanyId=@CompanyId
				and cp.StartDate>=@StartDate
				and cp.EndDate<=@EndDate
				and left(ac.SaftAccountCode,2) in ('40','41')
				and ac.AccSystemId=@AccSystemId
			group by ac.SaftAccountCode, ac.AccountType, a.PartnerId, ac.AccountType

			update a
			set OpeningDebitBalance=iif(a.AccountType='Activ' or (a.AccountType='Bifunctional' and a.OpeningDebitBalanceIni>=a.OpeningCreditBalanceIni) 
										,a.OpeningDebitBalanceIni-a.OpeningCreditBalanceIni
										,null),
				OpeningCreditBalance=iif(a.AccountType='Pasiv' or (a.AccountType='Bifunctional' and a.OpeningDebitBalanceIni<a.OpeningCreditBalanceIni) 
										,a.OpeningCreditBalanceIni-a.OpeningDebitBalanceIni
										,null)
			from #PartnerAccount a

			update a
			set ClosingDebitBalance=case when a.AccountType='Activ' then isnull(a.OpeningDebitBalance,0)+a.TurnOverDebit-a.TurnOverCredit
										when a.AccountType='Bifunctional' and isnull(a.OpeningDebitBalance,0)-isnull(a.OpeningCreditBalance,0)+a.TurnOverDebit-a.TurnOverCredit>0
											then isnull(a.OpeningDebitBalance,0)-isnull(a.OpeningCreditBalance,0)+a.TurnOverDebit-a.TurnOverCredit
										else null end,
				ClosingCreditBalance=case when a.AccountType='Pasiv' then isnull(a.OpeningCreditBalance,0)+a.TurnOverCredit-a.TurnOverDebit
										when a.AccountType='Bifunctional' and isnull(a.OpeningCreditBalance,0)-isnull(a.OpeningDebitBalance,0)-a.TurnOverDebit+a.TurnOverCredit>0
											then isnull(a.OpeningCreditBalance,0)-isnull(a.OpeningDebitBalance,0)-a.TurnOverDebit+a.TurnOverCredit
										else null end 
			from #PartnerAccount a

			create index Idx_#PartnerAccount_PartnerId on #PartnerAccount (PartnerId)

			update py
			set IsCustomer=iif(py.xType='Clienti',1,null),
				IsSupplier=iif(py.xType='Furnizori',1,null)
			from #PartnerAccount py
			where (isnull(py.OpeningDebitBalance,0)<>0 
				or isnull(py.OpeningCreditBalance,0)<>0 
				or isnull(py.ClosingDebitBalance,0)<>0 
				or isnull(py.ClosingCreditBalance,0)<>0
				or isnull(py.TurnOverDebit,0)<>0
				or isnull(py.TurnOverCredit,0)<>0)

			if not exists (select 1 from #PartnerAccount where IsCustomer=1)
			set @Customers=0
			/*begin
				set @RefKeyId=null
				
				select top 1 @RefKeyId=PartnerId 
				from #PartnerAccount py
				where py.xType='Clienti'

				if @RefKeyId is not null
				begin
					update py
					set IsCustomer=1
					from #PartnerAccount py
					where py.PartnerId=@RefKeyId
				end
				else
				begin
					set @MessageRO='Lipsa inregistrari in sectiunea Clienti'
					set @MessageEN='No records in the Customers section'

					insert into #ActionLogError 
						(ActionId, Flag, ErrorName, ErrorInfo)
					select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
				end
			end*/

			if not exists (select 1 from #PartnerAccount where IsSupplier=1)
			set @Suppliers=0
			/*begin
				set @RefKeyId=null
				
				select top 1 @RefKeyId=PartnerId 
				from #PartnerAccount py
				where py.xType='Furnizori'

				if @RefKeyId is not null
				begin
					update py
					set IsSupplier=1
					from #PartnerAccount py
					where py.PartnerId=@RefKeyId
				end
				else
				begin
					set @MessageRO='Lipsa inregistrari in sectiunea Furnizori'
					set @MessageEN='No records in the Suppliers section'

					insert into #ActionLogError 
						(ActionId, Flag, ErrorName, ErrorInfo)
					select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
				end
			end*/

			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, EndTime=getdate(), @SessionId, @@SpId
			
			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: Customers='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
		end

		TaxTable:
		if exists (select 1 from #ReportStructure where StrCode='2.5')
		begin
			set @TaxTable=1
			set @StepActionId=29 /*MasterFiles - Tax Table*/
			set @TimeStamp=getdate()

			insert into #xTaxTable (TaxCode)
			select gl.TaxCode
			from dbo.CalendarPeriod cp (nolock) 
			join Saft.GeneralLedgerEntriesPrep gl (nolock) on cp.CalendarPeriodId=gl.CalendarPeriodId
			where gl.CompanyId=@CompanyId
				and cp.StartDate>=@StartDate
				and cp.EndDate<=@EndDate
			group by gl.TaxCode

			insert into #TaxTable
				(TaxType, TaxTypeDescription, TaxCode, TaxPercentage, BaseRate, Country)
			select '300','Taxa pe valoarea adaugata',v.TaxCode, isnull(v.TaxPercent,0),0, 'RO' 
			from #xTaxTable gl
			join Saft.TaxVAT v (nolock) on gl.TaxCode=v.TaxCode and TaxVersion=@TaxVersionVAT

			insert into #TaxTable
				(TaxType, TaxTypeDescription, TaxCode, TaxPercentage, BaseRate, Country)
			select t.TaxType, t.TaxTypeDescription, '39'+substring(t.TaxCode,3,6), t.TaxPercentage, t.BaseRate, t.Country
			from #TaxTable t
			where t.TaxType='300'
				and left(t.TaxCode,2)='34'

			insert into #TaxTable
				(TaxType, TaxTypeDescription, TaxCode, TaxPercentage, Amount, CurrencyCode, CurrencyAmount, BaseRate, Country)
			select tt.TaxType, tt.TaxName, isnull(wht.TaxCode,'000000'), 0, sum(abd.EquivalentPostingValue), 'RON', sum(abd.EquivalentPostingValue), 0, 'RO' 
			from Saft.TaxType tt (nolock)
			left join Saft.TaxWHT wht (nolock) on tt.TaxType=wht.TaxType
			join dbo.Item it (nolock) on it.SaftTaxCode=isnull(wht.TaxCode,tt.TaxType)
			join Saft.AccBillDetail abd (nolock) on it.ItemId=abd.ItemId
			join dbo.CalendarPeriod cp (nolock) on abd.CalendarPeriodId=cp.CalendarPeriodId
			where abd.CompanyId=@CompanyId
				and cp.StartDate>=@StartDate
				and cp.EndDate<=@EndDate
			group by tt.TaxType, tt.TaxName, wht.TaxCode
			
			select @CountSection=count(1) from #TaxTable
			
			if @CountSection=0
			begin
				insert into #TaxTable
					(TaxType, TaxTypeDescription, TaxCode, TaxPercentage, BaseRate, Country)
				select top 3 '300','Taxa pe valoarea adaugata',v.TaxCode, isnull(v.TaxPercent,0),0, 'RO' 
				from Saft.TaxVAT v (nolock)
				where TaxVersion=@TaxVersionVAT
			end

			select @CountSection=count(1) from #TaxTable
			
			if @CountSection=0
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Tabela taxe'
				set @MessageEN='No records in the Tax Table section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end

			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, getdate(), @SessionId, @@SpId

			if @DeBug=97 select '#TaxTable', NrInreg=count(1) from #TaxTable


			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: TaxTable='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
		end

		UOMTable:
		if exists (select 1 from #ReportStructure where StrCode='2.6')
		begin
			set @UOMTable=1
			set @StepActionId=30 /*MasterFiles - UOMTable*/
			set @TimeStamp=getdate()

			; with xDocUM as (
				select dd.MeasuringUnitId
				from dbo.CalendarPeriod cp (nolock)
				join Saft.DocumentDetail dd (nolock) on cp.CalendarPeriodId=dd.CalendarPeriodId
				join dbo.Item it (nolock) on dd.ItemId=it.ItemId
				where dd.CompanyId=@CompanyId
					and cp.StartDate>=@StartDate
					and cp.EndDate<=@EndDate
					and it.IsStockable=1)
			
			, xStocUM as ( 
				select MeasuringUnitId=it.MeasuringUnitId
				from Item it (nolock)
				join Saft.StockMovements st (nolock) on it.ItemId=st.ItemId
				where st.CompanyId=@CompanyId
				and ((st.AtDate=@StartDate and st.OpType='SoldIni')
						or (st.AtDate=@EndDate and st.OpType='SoldFin')))

			, xUM as (
				select a.MeasuringUnitId,
					RowNumber=row_number() over(partition by MeasuringUnitId order by MeasuringUnitId)
				from (
					select MeasuringUnitId from xDocUM
					union all
					select MeasuringUnitId from xStocUM) a
				where a.MeasuringUnitId is not null)

			insert into #MeasuringUnit
				(MeasuringUnitId)
			select MeasuringUnitId
			from xUM 
			where RowNumber=1
			
			if @@rowcount=0
			insert into #MeasuringUnit
				(MeasuringUnitId)
			select top 1 a.MeasuringUnitId 
			from Saft.MapMeasuringUnit a (nolock)
			where a.SaftCode in ('XPP','KGM')

			select @CountSection=count(1) from #MeasuringUnit

			if @CountSection=0
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Tabela Unităților de Măsură'
				set @MessageEN='No records in the UOMTable section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end

			update a
			set SaftCode=x.SaftCode,
				SaftName=mu.ItemName
			from #MeasuringUnit a
			join dbo.DictionaryItem mu (nolock) on a.MeasuringUnitId=mu.ItemId and mu.DictionaryId=-1
			join Saft.MapMeasuringUnit x (nolock) on a.MeasuringUnitId=x.MeasuringUnitId
			where isnull(x.SaftCode,'')<>''

			select @ErrorMessage=string_agg(mu.ItemCode,'; ')
			from #MeasuringUnit a
			join dbo.DictionaryItem mu (nolock) on a.MeasuringUnitId=mu.ItemId and mu.DictionaryId=-1
			where isnull(a.SaftCode,'')=''
			
			if isnull(@ErrorMessage,'')<>''
			begin
				set @MessageRO='UM nemapate'
				set @MessageEN='Unmapped UM'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),@ErrorMessage
			end

			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, EndTime=getdate(), @SessionId, @@SpId

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: UOMTable='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
		end

		AnalysisTypeTable:
		if exists (select 1 from #ReportStructure where StrCode='2.7')
		begin
			set @AnalysisTypeTable=1
			set @StepActionId=31 /*MasterFiles - AnalysisTypeTable*/
			set @TimeStamp=getdate()
			
			insert into #AnalysisTypeTable
				(AnalysisType, AnalysisTypeDescription, AnalysisID, AnalysisIDDescription)
			select 'DEP', 'Departament', left(sa.StockAdminCode,35), sa.StockAdminName
			from dbo.CompanyLocation cl (nolock)
			join dbo.StockAdministration sa (nolock) on cl.LocationId=sa.LocationId
			where cl.CompanyId=@CompanyId
			
			select @CountSection=count(1) from #AnalysisTypeTable
			
			if @CountSection=0
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Tabel tipuri analiză'
				set @MessageEN='No records in the AnalysisTypeTable section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end

			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, EndTime=getdate(), @SessionId, @@SpId

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: AnalysisTypeTable='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
		end

		MovementTypeTable:
		if exists (select 1 from #ReportStructure where StrCode='2.8')
		begin
			set @MovementTypeTable=1
			set @StepActionId=32 /*MasterFiles - MovementTypeTable*/
			set @TimeStamp=getdate()

			insert into #MovementTypeTable
				(MovementCode, MovementName)
			select MovementCode, MovementName
			from Saft.StockMovementType (nolock)

			select @CountSection=count(1) from #MovementTypeTable
			
			if @CountSection=0
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Tabel tipuri mișcări'
				set @MessageEN='No records in the MovementTypeTable section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end
			
			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, EndTime=getdate(), @SessionId, @@SpId

		end

		Products:
		if exists (select 1 from #ReportStructure where StrCode='2.9')
		begin
			set @Products=1
			set @StepActionId=33 /*MasterFiles - Products*/
			set @TimeStamp=getdate()

			insert into #Products
				(ItemId, ProductCode, Description, UOMBase, UOMStandard, UOMToUOMBaseConversionFactor)
			select it.ItemId, it.ItemCode, it.ItemName, it.SaftUMCode, it.SaftUMCode, 0
			from (
				select abd.ItemId
				from dbo.CalendarPeriod cl (nolock) 
				join Saft.AccBillDetail abd  with (index(Idx_AccBillDetail_2)) on cl.CalendarPeriodId=abd.CalendarPeriodId
				where abd.CompanyId=@CompanyId
					and cl.StartDate between @StartDate and @EndDate
				group by abd.ItemId
				) st
			join Saft.vwItem it on it.ItemId=st.ItemId
			where it.IsStockable=1

			if @@rowcount=0
			insert into #Products
				(ItemId, ProductCode, Description, UOMBase, UOMStandard, UOMToUOMBaseConversionFactor)
			select it.ItemId, it.ItemCode, it.ItemName, it.SaftUMCode, it.SaftUMCode, 0
			from (
				select abd.ItemId
				from dbo.CalendarPeriod cl (nolock) 
				join Saft.AccBillDetail abd  with (index(Idx_AccBillDetail_2)) on cl.CalendarPeriodId=abd.CalendarPeriodId
				where abd.CompanyId=@CompanyId
					and cl.StartDate between @StartDate and @EndDate
				group by abd.ItemId
				) st
			join Saft.vwItem it on it.ItemId=st.ItemId
			where it.IsStockable=0
				and isnull(it.SaftUMCode,'')<>''

			update p
			set ProductCommodityCode=isnull(dbo.GetItemNC8(p.ItemId,year(@YearEndDate)),'0')
			from #Products p

			select @CountSection=count(1) from #Products

			if @CountSection=0
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Produse'
				set @MessageEN='No records in the Products section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end

			update p
			set ProductCode=dbo.RemoveCharFromStr(isnull(p.ProductCode,''),0,1,0,0,1,0),
				Description=dbo.RemoveCharFromStr(isnull(p.Description,''),0,1,0,0,1,0)
			from #Products p

			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, EndTime=getdate(), @SessionId, @@SpId

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: Products='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
		end

		PhysicalStock:
		if exists (select 1 from #ReportStructure where StrCode='2.10')
		begin
			set @PhysicalStock=1
			set @StepActionId=24 /*MasterFiles - PhysicalStock*/
			set @TimeStamp=getdate()

			insert into #PhysicalStock
				(ItemId, WarehouseID, ProductCode, ProductType, 
				OwnerID, UOMPhysicalStock, UOMToUOMBaseConversionFactor, UnitPrice, 
				OpeningStockQuantity, OpeningStockValue, ClosingStockQuantity, ClosingStockValue)
			select it.ItemId, convert(varchar(35),st.StockAdminId), convert(varchar(70),it.ItemCode), left(it.ItemTypeCode,18),
				p.SaftPartnerId, it.SaftUMCode, 1, 0, 
				st.OpeningStockQuantity, st.OpeningStockValue, st.ClosingStockQuantity, st.ClosingStockValue
			from (
				select st.ItemId, st.StockAdminId, 
					OpeningStockQuantity=sum(iif(st.OpType='SoldIni',st.Qtty,0)),
					OpeningStockValue=sum(iif(st.OpType='SoldIni',st.Value,0)),
					ClosingStockQuantity=sum(iif(st.OpType='SoldFin',st.Qtty,0)),
					ClosingStockValue=sum(iif(st.OpType='SoldFin',st.Value,0))
				from Saft.StockMovements st (nolock)
				where st.CompanyId=@CompanyId
				and ((st.AtDate=@StartDate and st.OpType='SoldIni')
						or (st.AtDate=@EndDate and st.OpType='SoldFin'))
				group by st.ItemId, st.StockAdminId		
				) st
			left join dbo.StockAdministration sa (nolock) on st.StockAdminId=sa.StockAdminId
			left join Saft.vwPartner p on sa.OwnerId=p.PartnerId
			join Saft.vwItem it on it.ItemId=st.ItemId

			update p
			set StockAccountCommodityCode=isnull(dbo.GetItemNC8(p.ItemId,year(@YearEndDate)),'0')
			from #PhysicalStock p

			select @CountSection=count(1) from #PhysicalStock

			if @CountSection=0
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Stocuri'
				set @MessageEN='No records in the PhysicalStock section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end

			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, EndTime=getdate(), @SessionId, @@SpId

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: PhysicalStock='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
		end

		Owners:
		if exists (select 1 from #ReportStructure where StrCode='2.11')
		begin
			set @Owners=1
			set @StepActionId=25 /*MasterFiles - Owners*/
			set @TimeStamp=getdate()

			insert into #Owners
				(PartnerId, AccountId)
			select sa.OwnerId, st.AccountId
			from (
				select st.StockAdminId, st.AccountId
				from Saft.StockMovements st (nolock)
				where st.CompanyId=@CompanyId
				and ((st.AtDate=@StartDate and st.OpType='SoldIni')
						or (st.AtDate=@EndDate and st.OpType='SoldFin'))
				group by st.StockAdminId, st.AccountId
				) st
			left join dbo.StockAdministration sa (nolock) on st.StockAdminId=sa.StockAdminId
			group by sa.OwnerId, st.AccountId

			if @@rowcount=0
			insert into #Owners
				(PartnerId, AccountId)
			select @SelfPartnerId, @FakeAccountId

			select @CountSection=count(1) from #Owners

			if @CountSection=0
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Proprietari'
				set @MessageEN='No records in the Owners section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end

			update o
			set SaftAccountCode=ac.SaftAccountCode
			from #Owners o
			join Saft.vwAccountChart ac on o.AccountId=ac.AccountId
			where ac.AccSystemId=@AccSystemId

			create index Idx_#Owners_PartnerId on #Owners (PartnerId)

			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, EndTime=getdate(), @SessionId, @@SpId

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: Owners='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
		end

		Assets:
		if exists (select 1 from #ReportStructure where StrCode='2.12')
		begin
			set @Assets=1
			set @StepActionId=26 /*MasterFiles - Assets*/
			set @TimeStamp=getdate()

			insert into #Assets
				(AssetCardId, AccountId, SaftAccountCode, [Description], DateOfAcquisition, StartUpDate, 
				ValuationClass, 	AssetLifeYear, AssetLifeMonth,
				AcquisitionAndProductionCostsBegin,
				AcquisitionAndProductionCostsEnd,
				BookValueBegin,
				BookValueEnd,
				InvestmentSupport,
				AssetAddition,
				Transfers,
				AssetDisposal,
				DepreciationForPeriod,
				AppreciationForPeriod,
				AccumulatedDepreciation,
				DepreciationMethod, 
				DepreciationPercentage,
				ExtraordinaryDepreciationMethod, 
				ExtraordinaryDepreciationAmountForPeriod)
			select ac.AssetCardId, ap.AccountId, ax.SaftCode,[Description]=ac.InventoryNo, 
				DateOfAcquisition=ac.ReceptionDate, 
				StartUpDate=ac.CommissioningDate, 
				ValuationClass=ac.AssetClassCode, AssetLifeYear=null, AssetLifeMonth=ap.AssetLifeMonth, 
				ap.AcquisitionAndProductionCostsBegin, ap.AcquisitionAndProductionCostsEnd, 
				ap.BookValueBegin, ap.BookValueEnd, 
				ap.InvestmentSupport, ap.AssetAddition,
				isnull(ap.Transfers,0), 
				isnull(ap.AssetDisposal,0), 
				isnull(ap.DepreciationForPeriod,0), 
				isnull(ap.AppreciationForPeriod,0), 
				isnull(ap.AccumulatedDepreciation,0), 
				DepreciationMethod=isnull(dia.ItemName,'LINIARA'),
				ap.DepreciationPercentage,
				ExtraordinaryDepreciationMethod='null',
				ap.ExtraordinaryDepreciationForPeriod
			from Saft.AssetCard ac (nolock) 
			join Saft.Log_AssetCardPeriod ap (nolock) on ac.AssetCardId=ap.AssetCardId and ac.CompanyId=ap.CompanyId
			left join Saft.MapAccountChart ax (nolock) on ac.AccountId=ax.AccountId and ax.AccSystemId=@AccSystemId
			left join DictionaryItem dia (nolock) on ap.DepreciationTypeId=dia.ItemId and dia.DictionaryId=@Id_DeprecType
			where ap.CompanyId=@CompanyId
				and ap.CalendarId=@CalendarId

			select @CountSection=count(1) from #Assets

			if @CountSection=0
			set @Assets=0
			
			if @CountSection=0 and 1=2
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Active'
				set @MessageEN='No records in the Assets section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end
			
			delete @TempErrorInfo
			
			insert into @TempErrorInfo 
				(ErrorInfo)
			select AssetClass=isnull(ac.ValuationClass,'')+' [Nr Inv: '+string_agg(convert(varchar(max), ac.[Description]),'; ')+']'
			from #Assets ac
			left join Saft.AssetClass cls (nolock) on isnull(ac.ValuationClass,'')=cls.AssetClassCode
			where isnull(ac.ValuationClass,'')<>''
				and isnull(cls.AssetClassCode,'')=''
			group by isnull(ac.ValuationClass,'')

			if exists (select 1 from @TempErrorInfo)
			begin
				set @MessageRO='Clasa incorecta'
				set @MessageEN='ValuationClass is incorrect'

				insert into #ActionLogError
					(ActionId, Flag, ErrorName, ErrorInfo)		
				select @StepActionId, 1, iif(@Language='RO',@MessageRO,@MessageEN), x.ErrorInfo
				from @TempErrorInfo x
			
				delete @TempErrorInfo
			end	

			insert into @TempErrorInfo 
				(ErrorInfo)
			select iif(@Language='RO','Nr Inv','InventoryNo')+': '+x.NrInv	
			from (
				select NrInv=string_agg(convert(varchar(max), isnull(a.[Description],'.')),'; ')
				from #Assets a
				where isnull(ValuationClass,'')=''
				) x
			where isnull(x.NrInv,'')<>''

			if exists (select 1 from @TempErrorInfo)
			begin
				set @MessageRO='Lipsa Clasa'
				set @MessageEN='ValuationClass is missing'

				insert into #ActionLogError
					(ActionId, Flag, ErrorName, ErrorInfo)		
				select @StepActionId, 1, iif(@Language='RO',@MessageRO,@MessageEN), x.ErrorInfo
				from @TempErrorInfo x
			
				delete @TempErrorInfo
			end	

			insert into @TempErrorInfo 
				(ErrorInfo)
			select iif(@Language='RO','Nr Inv','InventoryNo')+': '+string_agg(convert(varchar(max), a.Description),'; ')	
			from #Assets a
			where isnull(AssetLifeMonth,-1)=-1

			if exists (select 1 from @TempErrorInfo x where isnull(ErrorInfo,'')<>'')
			begin
				set @MessageRO='Lipsa perioada de viata utila in luni'
				set @MessageEN='Period of useful life in months is missing'

				insert into #ActionLogError
					(ActionId, Flag, ErrorName, ErrorInfo)		
				select @StepActionId, 1, iif(@Language='RO',@MessageRO,@MessageEN), x.ErrorInfo
				from @TempErrorInfo x
			
				delete @TempErrorInfo
			end	

			update #Assets set DepreciationPercentage=isnull(DepreciationPercentage,0)
			--update #Assets set AssetLifeMonth=isnull(AssetLifeMonth,1)
			--update #Assets set ValuationClass=isnull(ValuationClass,'1')

			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, EndTime=getdate(), @SessionId, @@SpId

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: Assets='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
		end

		GeneralLedgerEntries:
		if exists (select 1 from #ReportStructure where StrCode='3')
		begin
			set @GeneralLedgerEntries=1
			set @StepActionId=34 /*GeneralLedgerEntries*/
			set @TimeStamp=getdate()
			if @DeBug<>0  print 'GeneralLedgerEntries'

			insert into #GeneralLedgerEntries
				(CompanyId, CalendarPeriodId, xType, SaftAccountCode, PartnerId, 
				AccBillKeyId, PostingKeyId, DocumentKeyId, DocumentDetailKeyId,
				TransactionDate, SystemEntryDate, Description, LineDescription, 
				CurrencyAmount, Amount, CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBase, TaxAmount, 
				TaxBaseDescription, TaxCurrencyCode, TaxInv, DocTypeId, IsTaxVAT, RowD300, InvoiceTypeCode, VATId)
			select a.CompanyId, a.CalendarPeriodId, a.xType, a.SaftAccountCode, a.PartnerId, 
				a.AccBillKeyId, a.PostingKeyId, a.DocumentKeyId, a.DocumentDetailKeyId,
				a.TransactionDate, a.SystemEntryDate, a.Description, a.LineDescription, 
				a.CurrencyAmount, a.Amount, a.CurrencyCode, a.ExchangeRate, 
				TaxType=a.TaxType, a.TaxCode, a.TaxPercentage, a.TaxBase, a.TaxAmount, 
				a.TaxBaseDescription, a.TaxCurrencyCode, a.TaxInv, a.DocTypeId, a.IsTaxVAT, a.RowD300, a.InvoiceTypeCode, a.VATId
			from Saft.vwGeneralLedgerEntries a
			join dbo.CalendarPeriod cp (nolock) on a.CalendarPeriodId=cp.CalendarPeriodId
			where a.CompanyId=@CompanyId
				and cp.StartDate between @StartDate and @EndDate
			
			update ge
			set PartnerId=@SelfPartnerId
			from #GeneralLedgerEntries ge
			where ge.PartnerId is null

			create index Idx_GLE2 on #GeneralLedgerEntries (CompanyId, DocumentKeyId, DocumentDetailKeyId,SaftAccountCode)
			create index Idx_#GLE_PartnerId on #GeneralLedgerEntries (PartnerId)

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: GeneralLedgerEntries='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
			
			select @CountGL=count(1) from #GeneralLedgerEntries
			select @CountSection=@CountGL

			select @CountSection=count(1) from #GeneralLedgerEntries

			if @CountSection=0
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Înregistrări Contabile - Registrul Jurnal'
				set @MessageEN='No records in the GeneralLedgerEntries section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end

			select @GroupGL=case when @CountGL>=300000 then 1 when @CountGL>=100000 then 2 else 0 end

			if @DeBug=99
			print '		@CountGL:'+convert(varchar,@CountGL)+'; @GroupGL:'+(convert(varchar,@GroupGL))
			
			if @DeBug=98
			select '#GeneralLedgerEntries', * from #GeneralLedgerEntries

			if @GroupGL=0
				insert into #xGeneralLedgerEntries
					(xType, SaftAccountCode, PartnerId, PostingKeyId, AccBillKeyId,  Description, 
					TransactionDate, SystemEntryDate,
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode,
					CurrencyAmount, Amount, TaxBase, TaxAmount)
				select xType, SaftAccountCode, PartnerId, PostingKeyId, AccBillKeyId,  Description, 
					TransactionDate, SystemEntryDate,
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode,
					CurrencyAmount, Amount, TaxBase, TaxAmount
				from #GeneralLedgerEntries
			else
			if @GroupGL=1
				insert into #xGeneralLedgerEntries
					(xType, SaftAccountCode, PartnerId, PostingKeyId, AccBillKeyId,  Description, 
					TransactionDate, SystemEntryDate,
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode,
					CurrencyAmount, Amount, TaxBase, TaxAmount)
				select xType, SaftAccountCode, PartnerId, 
					PostingKeyId=min(PostingKeyId),
					AccBillKeyId=max(AccBillKeyId), 
					Description=max(Description), 
					TransactionDate, SystemEntryDate, 
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode,
					CurrencyAmount=sum(CurrencyAmount), 
					Amount=sum(Amount), 
					TaxBase=sum(TaxBase), 
					TaxAmount=sum(TaxAmount)			
				from #GeneralLedgerEntries
				where DocTypeId not in (1005,4032) 
					or (DocTypeId in (1005,4032) and isnull(InvoiceTypeCode,'')<>'751')
				group by xType, SaftAccountCode, PartnerId, DocTypeId,TransactionDate, SystemEntryDate, 
					iif(DocTypeId=8007,AccBillKeyId,null),
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode
			else
				insert into #xGeneralLedgerEntries
					(xType, SaftAccountCode, PartnerId, PostingKeyId, AccBillKeyId,  Description, 
					TransactionDate, SystemEntryDate,
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode,
					CurrencyAmount, Amount, TaxBase, TaxAmount)
				select xType, SaftAccountCode, PartnerId, 
					PostingKeyId=min(PostingKeyId),
					AccBillKeyId=AccBillKeyId, 
					Description=Description, 
					TransactionDate, SystemEntryDate, 
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode,
					CurrencyAmount=sum(CurrencyAmount), 
					Amount=sum(Amount), 
					TaxBase=sum(TaxBase), 
					TaxAmount=sum(TaxAmount)			
				from #GeneralLedgerEntries
				where DocTypeId not in (1005,4032) 
					or (DocTypeId in (1005,4032) and isnull(InvoiceTypeCode,'')<>'751')
				group by xType, SaftAccountCode, PartnerId, DocTypeId,
					AccBillKeyId, Description, 
					TransactionDate, SystemEntryDate, 
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode

			create index Idx_#xGLE_PartnerId on #xGeneralLedgerEntries (PartnerId)
			create index Idx_#xGLE_AccBillKeyId on #xGeneralLedgerEntries (AccBillKeyId)
				
			update p
			set Description=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.Description,''))),
				LineDescription=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.LineDescription,'')))
			from #xGeneralLedgerEntries p


			if @DeBug=99
			begin 
				declare @CountxGL int
				select @CountxGL=count(1) from #xGeneralLedgerEntries
				print '		@CountGL:'+convert(varchar,@CountGL)+'; @GroupGL:'+(convert(varchar,@GroupGL))+'; @CountxGL:'+(convert(varchar,@CountxGL))				
			end

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: xGeneralLedgerEntries='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
	
			/*
			if @GroupGL>0
			begin
				
				if @GroupGL=1
				insert into #xGeneralLedgerEntries
					(xType, SaftAccountCode, PartnerId, PostingKeyId, AccBillKeyId,  Description, 
					TransactionDate, SystemEntryDate,
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode,
					CurrencyAmount, Amount, TaxBase, TaxAmount)
				select xType, SaftAccountCode, PartnerId, 
					PostingKeyId=min(PostingKeyId),
					AccBillKeyId=max(AccBillKeyId), 
					Description=max(Description), 
					TransactionDate, SystemEntryDate, 
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode,
					CurrencyAmount=sum(CurrencyAmount), 
					Amount=sum(Amount), 
					TaxBase=sum(TaxBase), 
					TaxAmount=sum(TaxAmount)			
				from #GeneralLedgerEntries
				where DocTypeId not in (1005,4032) 
					or (DocTypeId in (1005,4032) and isnull(InvoiceTypeCode,'')<>'751')
				group by xType, SaftAccountCode, PartnerId, DocTypeId,TransactionDate, SystemEntryDate, 
					iif(DocTypeId=8007,AccBillKeyId,null),
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode
				else
				insert into #xGeneralLedgerEntries
					(xType, SaftAccountCode, PartnerId, PostingKeyId, AccBillKeyId,  Description, 
					TransactionDate, SystemEntryDate,
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode,
					CurrencyAmount, Amount, TaxBase, TaxAmount)
				select xType, SaftAccountCode, PartnerId, 
					PostingKeyId=min(PostingKeyId),
					AccBillKeyId=AccBillKeyId, 
					Description=Description, 
					TransactionDate, SystemEntryDate, 
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode,
					CurrencyAmount=sum(CurrencyAmount), 
					Amount=sum(Amount), 
					TaxBase=sum(TaxBase), 
					TaxAmount=sum(TaxAmount)			
				from #GeneralLedgerEntries
				where DocTypeId not in (1005,4032) 
					or (DocTypeId in (1005,4032) and isnull(InvoiceTypeCode,'')<>'751')
				group by xType, SaftAccountCode, PartnerId, DocTypeId,
					AccBillKeyId, Description, 
					TransactionDate, SystemEntryDate, 
					CurrencyCode, ExchangeRate, TaxType, TaxCode, TaxPercentage, TaxBaseDescription, TaxCurrencyCode
				
				create index Idx_#xGLE_PartnerId on #xGeneralLedgerEntries (PartnerId)
				create index Idx_#xGLE_AccBillKeyId on #xGeneralLedgerEntries (AccBillKeyId)
				
				update p
				set Description=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.Description,''))),
					LineDescription=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.LineDescription,'')))
				from #xGeneralLedgerEntries p

				if @DeBug=99
				begin 
					declare @CountxGL int
					select @CountxGL=count(1) from #xGeneralLedgerEntries
					print '		@CountGL:'+convert(varchar,@CountGL)+'; @GroupGL:'+(convert(varchar,@GroupGL))+'; @CountxGL:'+(convert(varchar,@CountxGL))				
				end

				if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
				begin
					print '	Prep: xGeneralLedgerEntries='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
					set @TimeStamp=getdate()
				end

			end
			else
			begin
				update p
				set Description=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.Description,''))),
					LineDescription=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.LineDescription,'')))
				from #GeneralLedgerEntries p
			end
			*/

			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, EndTime=getdate(), @SessionId, @@SpId

		end

		SalesInvoice:
		if exists (select 1 from #ReportStructure where StrCode='4.1')
		begin
			set @PurchaseInvoice=1
			set @SalesInvoice=1
			set @StepActionId=36 /*SourceDocuments - Invoices*/
			if @DeBug<>0  print 'SalesInvoice'
			
			exec Saft.UspGenerateXml_SourceDocInvoice @CompanyId, @Language, @StartDate, @EndDate, 3, @UserId, @SessionId

			select @CountSection=count(1) from #Invoice

			if @CountSection=0 and 1=2
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Facturi de Vanzare / Facturi de Achizitii'
				set @MessageEN='No records in the Sales Invoices / Purchase Invoices section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end
			
			if @DeBug=99 
			delete #Invoice where AccountId_H is null
			
			update p
			set DocumentNumber=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.DocumentNumber,''))),
				ProductCode=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.ProductCode,''))),
				ProductDescription=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.ProductDescription,''))),
				Description=isnull(nullif(dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.Description,''))),''),'x')
			from #Invoice p

			update Saft.UserActionLogHistory 
			set EndTime=getdate()
			where SessionId=@SessionId
				and ActionId=@StepActionId 
				and CompanyId=@CompanyId

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: SalesInvoice='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
		end

		Payment:
		if exists (select 1 from #ReportStructure where StrCode='4.3')
		begin		
			set @Payment=1
			set @StepActionId=37 /*SourceDocuments - Payments*/
			if @DeBug<>0  print 'Payment'			

			exec Saft.UspGenerateXml_SourceDocPayment @CompanyId, @Language, @StartDate, @EndDate, 3, @UserId, @SessionId

			update p
			set DocumentNumber=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.DocumentNumber,''))),
				RefDocumentNumber=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.RefDocumentNumber,''))),
				Description=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.Description,'')))
			from #Payment p

			select @CountSection=count(1) from #Payment

			if @CountSection=0
			set @Payment=0
			/*begin
				set @MessageRO='Lipsa inregistrari in sectiunea Plăți'
				set @MessageEN='No records in the Payments section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end*/

			update Saft.UserActionLogHistory 
			set EndTime=getdate()
			where SessionId=@SessionId
				and ActionId=@StepActionId 
				and CompanyId=@CompanyId

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: Payment='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
		end

		AssetTransaction:
		if exists (select 1 from #ReportStructure where StrCode='4.5')
		begin		
			set @AssetTransactions=1
			set @StepActionId=39 /*Asset Transactions*/
			if @DeBug<>0  print 'Asset Transactions'			
				
			insert into #AssetTransaction
				(AssetCardId, JournalId, TransactionId, 	TransactionCode, [Description], 
				TransactionDate, AcquisitionAndProductionCosts, BookValue, Amount)
			select AssetCardId, JournalId, TransactionId, TransactionCode, [Description],
				TransactionDate, isnull(AcquisitionAndProductionCosts,0), isnull(BookValue,0), isnull(Amount,0)
			from Saft.Log_AssetTransaction (nolock)
			where CompanyId=@CompanyId
				and CalendarId=@CalendarId

			update a
			set TransactionId=isnull(a.TransactionId,a.JournalId)
			from #AssetTransaction a
			
			if exists (select 1 from #AssetTransaction a where a.TransactionId is null)
			begin
				set @MessageRO='Lipsa Document referinta'
				set @MessageEN='Reference Document is missing'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 1, iif(@Language='RO',@MessageRO,@MessageEN),null

				delete a
				from #AssetTransaction a 
				where a.TransactionId is null
			end

			select @CountSection=count(1) from #AssetTransaction

			if @CountSection=0
			begin
				set @MessageRO='Lipsa inregistrari in sectiunea Tranzactii cu Active'
				set @MessageEN='No records in the Asset Transactions section'

				insert into #ActionLogError 
					(ActionId, Flag, ErrorName, ErrorInfo)
				select @StepActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),null
			end

			insert into Saft.UserActionLogHistory 
				(CompanyId, ActionId, StartDate, EndDate, UserId, StartTime, EndTime, SessionId, SpId)
			select @CompanyId, @StepActionId, @StartDate, @EndDate, @UserId, @TimeStamp, EndTime=getdate(), @SessionId, @@SpId

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: AssetTransaction='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end
		end
		
		Part:
		begin
			
			; with xPartner as (
				select a.PartnerId,
					RowNumber=row_number() over(partition by PartnerId order by PartnerId)
				from (
					select ge.PartnerId from #xGeneralLedgerEntries ge union all
					select py.PartnerId from #PartnerAccount py 
					where (py.IsCustomer=1 or py.IsSupplier=1)
					union all
					select py.PartnerId from #Payment py union all
					select o.PartnerId from #Owners o union all
					select i.PartnerId from #Invoice i) a)
			
			insert into #Partners
				(PartnerId)
			select a.PartnerId
			from xPartner a
			where RowNumber=1

			create index Idx_#Part on #Partners (PartnerId)

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: Create #Partners='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end

			update x
			set SaftPartnerId=p.SaftPartnerId, 
				PartnerName=left(dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.PartnerName,''))),70),
				City=dbo.RemoveIllegalCharXML(dbo.RemoveNonASCII(isnull(p.City,''))),
				District=p.District,
				Country=p.Country
			from #Partners x
			join Saft.vwPartner p on x.PartnerId=p.PartnerId

			if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
			begin
				print '	Prep: Update #Partners='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
				set @TimeStamp=getdate()
			end

		end

		PrepGLE:
		begin
			update t
			set SaftPartnerId=p.SaftPartnerId
			from #xGeneralLedgerEntries t
			join #Partners p on t.PartnerId=p.PartnerId


		end

		InvoiceFromSFN:
		begin
			if @GroupGL=0
			delete a 
			from #xGeneralLedgerEntries a
			where DocTypeId in (1005,4032) and isnull(InvoiceTypeCode,'')='751'
		end

	end

	update a
	set Flag=isnull(b.Flag,0),
		Error_msg=iif(isnull(a.Error_msg,'')='','',a.Error_msg+'; ')
					+iif(isnull(b.Error_msg,'')='','',b.Error_msg),
		InfoXml=b.InfoXml
	from Saft.UserActionLogHistory a
	left join (
		select a.ActionId, 
			Flag=max(a.Flag),
			Error_msg=string_agg(iif(a.Flag=1,iif(@Language='RO','Atentionare','Warning'),iif(@Language='RO','Eroare','Error'))+': '+a.ErrorName,'; '),
			InfoXml=cast((
				select Flag=b.Flag,
					CheckName=iif(b.Flag=1,iif(@Language='RO','Atentionare','Warning'),iif(@Language='RO','Eroare','Error'))+': '+b.ErrorName, 
					CheckInfo=isnull(b.ErrorInfo,'')		
				from #ActionLogError b
				where a.ActionId=b.ActionId
				for xml path('Check'), root('root')) as xml)
		from (
			select a.ActionId, a.Flag, a.ErrorName
			from #ActionLogError a
			where isnull(a.ErrorName,'')<>''
			group by a.ActionId, a.Flag, a.ErrorName
			) a
		group by a.ActionId
		) b on a.ActionId=b.ActionId
	where a.SessionId=@SessionId
		and a.CompanyId=@CompanyId

	if exists (
		select 1 from #ActionLogError a where a.Flag=2)
	goto HasError	

	if @DeBug not in (0,99)   goto EndOfProc

	if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
	begin
		print '	Prep: Clean table='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
		set @TimeStamp=getdate()
	end

	create nonclustered index IX_GLE_AccBillKeyId on #GeneralLedgerEntries(AccBillKeyId);
	create nonclustered index IX_Invoice_DocumentKeyId on #Invoice(DocumentKeyId);
	create nonclustered index IX_Payment_HashKey_H on #Payment(HashKey_H);

	set @TimeStamp=getdate()

	declare  
		@HeaderXML xml,
		@MasterFilesXML xml,
		@GeneralLedgerEntriesXML xml,
		@SourceDocumentsXML xml

	;with XMLNAMESPACES (default 'mfp:anaf:dgti:d406:declaratie:v1')
	select @HeaderXML=(
		select [AuditFileVersion]='2.0',
			[AuditFileCountry]='RO',
			[AuditFileDateCreated]=convert(date,getdate()),
			[SoftwareCompanyName]='AdoSoft Consulting SRL',
			[SoftwareID]='PyCube AnyPoint',
			[SoftwareVersion]=@SoftwareVersion,
			(select [RegistrationNumber]=@SelfCIF, 
				[Name]=c.PartnerName, 
				(select [StreetName]=c.Street,
					[Number]=c.LocalNumber,
					[AdditionalAddressDetail]=nullif(c.AdditionalAddressDetail,''),
					[City]=c.City, 
					[Region]=c.District,
					[Country]=c.Country
				for xml path('Address'), type),
				(select 
					(select [FirstName]=c.ContactPersonFirstName, 
						[LastName]=c.ContactPersonLastName
					for xml path('ContactPerson'), type), 
					[Telephone]=c.Telephone
				for xml path('Contact'), type),
				(select [IBANNumber]=ba.IBAN
				from dbo.fnPartnerBankAccount(c.PartnerId,@RON_Currency,0) ba
				for xml path('BankAccount'), type)
			from #Company c			
			for xml path('Company'), type),
			[DefaultCurrencyCode]='RON',
			(select [SelectionStartDate]=@StartDate, 
				[SelectionEndDate]=@EndDate
			for xml path('SelectionCriteria'), type), 
			[HeaderComment]=@ReportingType,
			[SegmentIndex]=@SegmentIndex,
			[TotalSegmentsInsequence]=@TotalSegmentsInsequence,
			[TaxAccountingBasis]=@AccSystemCode
		for xml path(''),type);

	;with XMLNAMESPACES (default 'mfp:anaf:dgti:d406:declaratie:v1')
	select @MasterFilesXML=(
		select
			iif(@GeneralLedgerAccounts=1,
				(select 
					[AccountID]=a.AccountID, 
					[AccountDescription]=a.AccountDescription, 
					[StandardAccountID]=a.StandardAccountID, 
					[AccountType]=a.AccountType, 
					[OpeningDebitBalance]=a.OpeningDebitBalance,
					[OpeningCreditBalance]=a.OpeningCreditBalance,
					[ClosingDebitBalance]=a.ClosingDebitBalance, 
					[ClosingCreditBalance]=a.ClosingCreditBalance
				from #GeneralLedgerAccounts a
				for xml path('Account'), root('GeneralLedgerAccounts'), type),
				(select x=null for xml path('GeneralLedgerAccounts'), type)),

			iif(@Customers=1,
				(select 
					(select 
						[RegistrationNumber]=p.SaftPartnerId, 
						[Name]=p.PartnerName,
						(select [City]=p.City, [Country]=p.Country
						 for xml path('Address'), type)
					for xml path('CompanyStructure'), type),
					[CustomerID]=p.SaftPartnerId, 
					[AccountID]=a.AccountID,
					[OpeningDebitBalance]=a.OpeningDebitBalance,
					[OpeningCreditBalance]=a.OpeningCreditBalance,
					[ClosingDebitBalance]=a.ClosingDebitBalance, 
					[ClosingCreditBalance]=a.ClosingCreditBalance
				from #PartnerAccount a
				join #Partners p on a.PartnerId=p.PartnerId
				where a.IsCustomer=1
				for xml path('Customer'), root('Customers'), type),
				(select x=null for xml path('Customers'), type)),

			iif(@Suppliers=1,
				(select 
					(select 
						[RegistrationNumber]=p.SaftPartnerId, 
						[Name]=p.PartnerName,
						(select [City]=p.City, [Country]=p.Country
						 for xml path('Address'), type)
					for xml path('CompanyStructure'), type),
					[SupplierID]=p.SaftPartnerId, 
					[AccountID]=a.AccountID,
					[OpeningDebitBalance]=a.OpeningDebitBalance,
					[OpeningCreditBalance]=a.OpeningCreditBalance,
					[ClosingDebitBalance]=a.ClosingDebitBalance, 
					[ClosingCreditBalance]=a.ClosingCreditBalance
				from #PartnerAccount a
				join #Partners p on a.PartnerId=p.PartnerId
				where a.IsSupplier=1
				for xml path('Supplier'), root('Suppliers'), type),
				(select x=null for xml path('Suppliers'), type)),

			iif(@TaxTable=1,
				(select [TaxType]=a.TaxType, 
						[Description]=a.TaxName,
						(select [TaxCode]=b.TaxCode, 
								[TaxPercentage]=b.TaxPercentage,
								[BaseRate]=b.BaseRate,
								[Country]=b.Country
						 from #TaxTable b
						 where a.TaxType=b.TaxType
						 for xml path('TaxCodeDetails'), type)
				 from (select tt.TaxType, tt.TaxName
					   from #TaxTable tx
					   join Saft.TaxType tt (nolock) on tx.TaxType=tt.TaxType
					   group by tt.TaxType, tt.TaxName) a
				 for xml path('TaxTableEntry'), root('TaxTable'), type),
				(select x=null for xml path('TaxTable'), type)),

			iif(@UOMTable=1,
				(select [UnitOfMeasure]=a.SaftCode,
						[Description]=min(a.SaftName)
				 from #MeasuringUnit a
				 group by a.SaftCode
				 for xml path('UOMTableEntry'), root('UOMTable'), type),
				(select x=null for xml path('UOMTable'), type)),

			iif(@AnalysisTypeTable=1,
				(select [AnalysisType]=a.AnalysisType,
						[AnalysisTypeDescription]=a.AnalysisTypeDescription,
						[AnalysisID]=a.AnalysisID,
						[AnalysisIDDescription]=a.AnalysisIDDescription
				 from #AnalysisTypeTable a
				 for xml path('AnalysisTypeTableEntry'), root('AnalysisTypeTable'), type),
				(select x=null for xml path('AnalysisTypeTable'), type)),

			iif(@MovementTypeTable=1,
				(select x=null for xml path('MovementTypeTable'), type),
				(select x=null for xml path('MovementTypeTable'), type)),

			iif(@Products=1,
				(select [ProductCode]=a.ProductCode, 
						[Description]=a.Description, 
						[ProductCommodityCode]=a.ProductCommodityCode, 
						[UOMBase]=a.UOMBase, 
						[UOMStandard]=a.UOMStandard, 
						[UOMToUOMBaseConversionFactor]=a.UOMToUOMBaseConversionFactor
				 from #Products a
				 for xml path('Product'), root('Products'), type),
				(select x=null for xml path('Products'), type)),

			iif(1=1,
				(select [WarehouseID]=a.WarehouseID, 
						[ProductCode]=a.ProductCode, 
						[ProductType]=a.ProductType, 
						[StockAccountCommodityCode]=a.StockAccountCommodityCode, 
						[OwnerID]=a.OwnerID, 
						[UOMPhysicalStock]=a.UOMPhysicalStock, 
						[UOMToUOMBaseConversionFactor]=a.UOMToUOMBaseConversionFactor, 
						[UnitPrice]=a.UnitPrice, 
						[OpeningStockQuantity]=a.OpeningStockQuantity, 
						[OpeningStockValue]=a.OpeningStockValue, 
						[ClosingStockQuantity]=a.ClosingStockQuantity, 
						[ClosingStockValue]=a.ClosingStockValue,
						(select [StockCharacteristic]=convert(varchar(10),'null'),
								[StockCharacteristicValue]=convert(varchar(10),'null')
						 for xml path('StockCharacteristics'), type)
				 from #PhysicalStock a
				 for xml path('PhysicalStockEntry'), root('PhysicalStock'), type),
				(select x=null for xml path('PhysicalStock'), type)),

			iif(@Owners=1,
				(select 
					(select 
						(select [RegistrationNumber]=p.SaftPartnerId, 
								[Name]=p.PartnerName, 
								(select [City]=p.City, [Country]=p.Country
								 for xml path('Address'), type)
						 for xml path('CompanyStructure'), type),
						 [OwnerID]=p.SaftPartnerId,
						 [AccountID]=o.SaftAccountCode
					from #Owners o
					join #Partners p on o.PartnerId=p.PartnerId
					for xml path('Owner'), type)
				 for xml path('Owners'), type),
				(select x=null for xml path('Owners'), type)),

			iif(@Assets=1,
				(select [AssetID]=a.AssetCardId,
						[AccountID]=a.SaftAccountCode,
						[Description]=a.[Description],
						[DateOfAcquisition]=a.DateOfAcquisition,
						[StartUpDate]=a.StartUpDate,
						(select
							(select [AssetValuationType]='CONTABILA', 
									[ValuationClass]=a.ValuationClass,
									[AcquisitionAndProductionCostsBegin]=a.AcquisitionAndProductionCostsBegin,
									[AcquisitionAndProductionCostsEnd]=a.AcquisitionAndProductionCostsEnd,
									[InvestmentSupport]=a.InvestmentSupport,
									[AssetLifeYear]=a.AssetLifeYear,
									[AssetLifeMonth]=a.AssetLifeMonth,
									[AssetAddition]=a.AssetAddition,
									[Transfers]=a.Transfers,
									[AssetDisposal]=a.AssetDisposal,
									[BookValueBegin]=a.BookValueBegin,
									[DepreciationMethod]=a.DepreciationMethod,
									[DepreciationPercentage]=a.DepreciationPercentage,
									[DepreciationForPeriod]=a.DepreciationForPeriod,
									[AppreciationForPeriod]=a.AppreciationForPeriod,
									(select
										(select [ExtraordinaryDepreciationMethod]=a.ExtraordinaryDepreciationMethod,
												[ExtraordinaryDepreciationAmountForPeriod]=a.ExtraordinaryDepreciationAmountForPeriod
										 for xml path('ExtraordinaryDepreciationForPeriod'), type)
									 for xml path('ExtraordinaryDepreciationsForPeriod'), type),
									[AccumulatedDepreciation]=a.AccumulatedDepreciation,
									[BookValueEnd]=a.BookValueEnd
							for xml path('Valuation'), type)
						 for xml path('Valuations'), type)
				 from #Assets a
				 for xml path('Asset') , root('Assets'), type),
				(select x=null for xml path('Assets'), type))
		for xml path(''), type);

	---------------------------------------
	--/*
	if @GeneralLedgerEntries=0
	with XMLNAMESPACES (default 'mfp:anaf:dgti:d406:declaratie:v1')
	select @GeneralLedgerEntriesXML=(select x=null for xml path(''), type)
	else
	with XMLNAMESPACES (default 'mfp:anaf:dgti:d406:declaratie:v1')
	select @GeneralLedgerEntriesXML=(
		select [NumberOfEntries]=gx.NumberOfEntries, 
			[TotalDebit]=gx.TotalDebit,
			[TotalCredit]=gx.TotalCredit,
			(select [JournalID]=1, 
				[Description]='Jurnal contabil',
				[Type]=1, 
				(select [TransactionID]=ge.AccBillKeyId,
					[Period]=month(ge.SystemEntryDate),
					[PeriodYear]=year(ge.SystemEntryDate),
					[TransactionDate]=ge.TransactionDate,
					[Description]=ge.Description,
					[SystemEntryDate]=ge.SystemEntryDate,
					[GLPostingDate]=ge.SystemEntryDate,
					[CustomerID]=@SelfSaftPartnerId,
					[SupplierID]='0',					
					(select [RecordID]=t.PostingKeyId, 
						[AccountID]=t.SaftAccountCode,
						[CustomerID]=iif(left(t.SaftAccountCode,2)='41',t.SaftPartnerId,@SelfSaftPartnerId),
						[SupplierID]=iif(left(t.SaftAccountCode,2)='40',t.SaftPartnerId,'0'),
						[Description]=isnull(nullif(t.LineDescription,''),'X'),
						iif(t.xType='D',							
							(select [Amount]=t.Amount,
								[CurrencyCode]=t.CurrencyCode, 
								[CurrencyAmount]=t.CurrencyAmount, 
								[ExchangeRate]=t.ExchangeRate 
							for xml path('DebitAmount'), type),
							(select [Amount]=t.Amount,
								[CurrencyCode]=t.CurrencyCode, 
								[CurrencyAmount]=t.CurrencyAmount, 
								[ExchangeRate]=t.ExchangeRate 
							for xml path('CreditAmount'), type)),
						(select [TaxType]=isnull(t.TaxType,'000'),
							[TaxCode]=isnull(t.TaxCode,'000000'),
							[TaxPercentage]=0, 
							[TaxBase]=t.TaxBase,									
							(select [Amount]=isnull(t.TaxAmount,0),
								[CurrencyCode]='RON', 
								[CurrencyAmount]=isnull(t.TaxAmount,0), 
								[ExchangeRate]=1
							for xml path('TaxAmount'), type)
						for xml path('TaxInformation'), type)
					from #xGeneralLedgerEntries t
					where t.AccBillKeyId=ge.AccBillKeyId 
					for xml path('TransactionLine'), type)
				from (
					select ge.AccBillKeyId, 
						TransactionDate=min(ge.TransactionDate),
						SystemEntryDate=min(ge.SystemEntryDate),	
						Description=max(isnull(nullif(ge.Description,''),'0'))
					from #xGeneralLedgerEntries ge
					group by ge.AccBillKeyId
					) ge
					for xml path('Transaction'), type)
			for xml path('Journal'), type)
		from (
			select NumberOfEntries=count(distinct PostingKeyId), 
				TotalDebit=sum(iif(a.xType='D',a.Amount,0)),
				TotalCredit=sum(iif(a.xType='C',a.Amount,0))
			from #xGeneralLedgerEntries a
			) gx
		for xml path(''), type)
	--*/

	;with XMLNAMESPACES (default 'mfp:anaf:dgti:d406:declaratie:v1')
	select @SourceDocumentsXML=(
		select 
			(select [NumberOfEntries]=ix.NumberOfEntries, 
				[TotalDebit]=ix.TotalDebit,
				[TotalCredit]=ix.TotalCredit,
				(select [InvoiceNo]=i.DocumentNumber, 
					(select [CustomerID]=p.SaftPartnerId,
						(select [City]=p.City,
							[Region]=p.District,
							[Country]=p.Country,
							[AddressType]='BillingAddress'
						for xml path('BillingAddress'), type)
					for xml path('CustomerInfo'), type), 
					[AccountID]=i.AccountId, 
					[InvoiceDate]=i.DocumentDate,
					[InvoiceType]=i.InvoiceTypeCode,
					[SelfBillingIndicator]=iif(i.InvoiceTypeCode='389',i.InvoiceTypeCode,'0'),
					(select [AccountID]=id.AccountId_D,
						[GoodsServicesID]=id.GoodsServicesID,
						[ProductCode]=id.ProductCode,
						[ProductDescription]=id.ProductCode,
						[Quantity]=id.Quantity,
						[UnitPrice]=id.UnitPrice,
						[TaxPointDate]=id.TaxPointDate,
						[Description]=id.Description,
						(select [Amount]=id.Amount,
							[CurrencyCode]=id.CurrencyCode,
							[CurrencyAmount]=id.CurrencyAmount,
							[ExchangeRate]=id.ExchangeRate
						for xml path('InvoiceLineAmount'), type),
						[DebitCreditIndicator]=id.DebitCreditIndicator,
						(select [TaxType]=dtx.TaxType,
							[TaxCode]=dtx.TaxCode,
							[TaxPercentage]=0, 
							[TaxBase]=dtx.TaxBase,									
							(select [Amount]=dtx.TaxAmount,
								[CurrencyCode]=dtx.TaxCurrencyCode, 
								[CurrencyAmount]=dtx.TaxAmount, 
								[ExchangeRate]=1
							for xml path('TaxAmount'), type)
						from #InvoiceTax dtx
						where dtx.DocumentDetailKeyId=id.DocumentDetailKeyId
						for xml path('TaxInformation'), type)
					from #Invoice id
					where id.DocumentKeyId=i.DocumentKeyId
					for xml path('InvoiceLine'), type)
				from (
					select i.DocumentTypeId, i.DocumentKeyId, i.DocumentNumber, i.DocumentDate, 
						i.PartnerId, i.PartnerAddressId, i.DeliveryAddressId, i.InvoiceTypeCode,
						TotalAmount=sum(i.Amount), AccountId=max(i.AccountId_H)
					from #Invoice i
					where left(i.DocumentTypeId,1)=1
					group by i.DocumentTypeId, i.DocumentKeyId, i.DocumentNumber, i.DocumentDate, 
						i.PartnerId, i.PartnerAddressId, i.DeliveryAddressId, i.InvoiceTypeCode
					) i
				join #Partners p on i.PartnerId=p.PartnerId
				for xml path('Invoice'), type)
				from (
					select NumberOfEntries=nullif(count(distinct i.DocumentKeyId),0), 
						TotalDebit=sum(i.Amount),
						TotalCredit=sum(i.Amount)
					from #Invoice i
					where left(i.DocumentTypeId,1)=1
					) ix
			for xml path('SalesInvoices'), type),

			(select [NumberOfEntries]=ix.NumberOfEntries, 
				[TotalDebit]=ix.TotalDebit,
				[TotalCredit]=ix.TotalCredit,
				(select [InvoiceNo]=i.DocumentNumber, 
					(select [SupplierID]=p.SaftPartnerId,
						(select [City]=p.City,
							[Region]=p.District,
							[Country]=p.Country,
							[AddressType]='BillingAddress'
						for xml path('BillingAddress'), type)
					for xml path('SupplierInfo'), type), 
					[AccountID]=i.AccountId, 
					[InvoiceDate]=i.DocumentDate,
					[InvoiceType]=i.InvoiceTypeCode,
					[SelfBillingIndicator]=iif(i.InvoiceTypeCode='389',i.InvoiceTypeCode,'0'),
					(select [AccountID]=id.AccountId_D,
						[GoodsServicesID]=id.GoodsServicesID,
						[ProductCode]=id.ProductCode,
						[ProductDescription]=id.ProductCode,
						[Quantity]=id.Quantity,
						[UnitPrice]=id.UnitPrice,
						[TaxPointDate]=id.TaxPointDate,
						[Description]=id.Description,
						(select [Amount]=id.Amount,
							[CurrencyCode]=id.CurrencyCode,
							[CurrencyAmount]=id.CurrencyAmount,
							[ExchangeRate]=id.ExchangeRate
						for xml path('InvoiceLineAmount'), type),
						[DebitCreditIndicator]=id.DebitCreditIndicator,
						(select [TaxType]=dtx.TaxType,
							[TaxCode]=dtx.TaxCode,
							[TaxPercentage]=0, 
							[TaxBase]=dtx.TaxBase,									
							(select [Amount]=dtx.TaxAmount,
								[CurrencyCode]=dtx.TaxCurrencyCode, 
								[CurrencyAmount]=dtx.TaxAmount, 
								[ExchangeRate]=1
							for xml path('TaxAmount'), type)
						from #InvoiceTax dtx
						where dtx.DocumentDetailKeyId=id.DocumentDetailKeyId 
						for xml path('TaxInformation'), type)
					from #Invoice id
					where id.DocumentKeyId=i.DocumentKeyId
					for xml path('InvoiceLine'), type)
				from (
					select i.DocumentTypeId, i.DocumentKeyId, i.DocumentNumber, i.DocumentDate, 
						i.PartnerId, i.PartnerAddressId, i.DeliveryAddressId, i.InvoiceTypeCode,
						TotalAmount=sum(i.Amount), AccountId=max(i.AccountId_H)
					from #Invoice i
					where left(i.DocumentTypeId,1)=3
					group by i.DocumentTypeId, i.DocumentKeyId, i.DocumentNumber, i.DocumentDate, 
						i.PartnerId, i.PartnerAddressId, i.DeliveryAddressId, i.InvoiceTypeCode
					) i 
				join #Partners p on i.PartnerId=p.PartnerId
				for xml path('Invoice'), type)
			from (
				select NumberOfEntries=nullif(count(distinct i.DocumentKeyId),0),
					TotalDebit=sum(i.Amount),
					TotalCredit=sum(i.Amount)
				from #Invoice i
				where left(i.DocumentTypeId,1)=3
				) ix
			for xml path('PurchaseInvoices'), type),

			(select [NumberOfEntries]=px.NumberOfEntries,
				[TotalDebit]=px.TotalDebit,
				[TotalCredit]=px.TotalCredit,
				(select [PaymentRefNo]=pz.DocumentKeyId, 
					[TransactionDate]=pz.DocumentDate,
					[PaymentMethod]=pz.PaymentMethod,
					[Description]=isnull(pz.Description,'x'),
					(select [AccountID]=py.AccountID,
						[CustomerID]=iif(py.DebitCreditIndicator='D',p.SaftPartnerId,'0'),
						[SupplierID]=iif(py.DebitCreditIndicator='C',p.SaftPartnerId,'0'),
						[TaxPointDate]=py.TaxPointDate,
						[DebitCreditIndicator]=py.DebitCreditIndicator,
						(select [Amount]=py.Amount,
							[CurrencyCode]=py.CurrencyCode,
							[CurrencyAmount]=py.CurrencyAmount,
							[ExchangeRate]=py.ExchangeRate
						for xml path('PaymentLineAmount'), type),
						(select [TaxType]=pyt.TaxType,
							[TaxCode]=pyt.TaxCode,
							[TaxPercentage]=0, 
							[TaxBase]=pyt.TaxBase,									
							(select [Amount]=pyt.TaxAmount,
								[CurrencyCode]='RON', 
								[CurrencyAmount]=pyt.TaxAmount, 
								[ExchangeRate]=1
							for xml path('TaxAmount'), type)
						from #PaymentTax pyt
						where py.HashKey_D=pyt.HashKey_D
						for xml path('TaxInformation'), type)
					from #Payment py
					left join #Partners p on py.PartnerId=p.PartnerId
					where py.HashKey_H=pz.HashKey_H
					for xml path('PaymentLine'), type)
				from (
					select py.HashKey_H, py.DocumentKeyId, py.DocumentDate, py.PaymentMethod,
						Description=max(py.Description)
					from #Payment py 
					group by py.HashKey_H, py.DocumentKeyId, py.DocumentDate, py.PaymentMethod
					) pz
				for xml path('Payment'), type)
			from (
				select NumberOfEntries=nullif(count(1),0),
					TotalDebit=sum(iif(py.DebitCreditIndicator='D',py.CurrencyAmount,0)),
					TotalCredit=sum(iif(py.DebitCreditIndicator='C',py.CurrencyAmount,0))
				from #Payment py
				) px
			for xml path('Payments'), type), 

			(select x=null for xml path('MovementOfGoods'), type),

			iif(@AssetTransactions=1,
				(select [NumberOfAssetTransactions]=tx.NumberOfEntries, 
					(select [AssetTransactionID]=a.TransactionId,
						[AssetID]=a.AssetCardId, 
						[AssetTransactionType]=a.TransactionCode, 
						[Description]=null,
						[AssetTransactionDate]=a.TransactionDate,
						[TransactionID]=a.TransactionId,							
						(select [AssetValuationType]='CONTABILA',
							[AcquisitionAndProductionCostsOnTransaction]=a.AcquisitionAndProductionCosts,
							[BookValueOnTransaction]=a.BookValue,
							[AssetTransactionAmount]=a.Amount
						for xml path('AssetTransactionValuation'), root('AssetTransactionValuations'))
					from #AssetTransaction a
					for xml path('AssetTransaction'), type)
				from (
					select NumberOfEntries=count(1)
					from #AssetTransaction
					) tx	
				for xml path('AssetTransactions'), type)
				,null)
	for xml path(''), type)

	declare @AuditFileXML xml;

	;with XMLNAMESPACES (default 'mfp:anaf:dgti:d406:declaratie:v1')
	select @AuditFileXML=(
		select @HeaderXML as [Header],
			@MasterFilesXML as [MasterFiles],
			@GeneralLedgerEntriesXML as [GeneralLedgerEntries],
			@SourceDocumentsXML as [SourceDocuments]
		for xml path(''), root('AuditFile'), type)

	set @AuditFile=cast(@AuditFileXML as nvarchar(max));

	if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
	begin
		print 'Prepare: @AuditFile='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
		set @TimeStamp=getdate()
	end
	
	begin try
	begin transaction ProcessXml
		set @vMessage=''
		
		if @Testing=1
		set @XmlD406T=cast(@AuditFile as xml)
		else
		set @XmlD406=cast(@AuditFile as xml)

	FinishProcessXml:
	begin
		if isnull(@vMessage,'')=''
		select @vMessage=isnull(error_message(),@vMessage)

		if isnull(@vMessage,'')<>'' raiserror(@vMessage,16,1)                           
	end  
	commit transaction ProcessXml;
        
	end try
	begin catch
                
		select @xstate=xact_state()

		if @xstate=-1  rollback transaction ProcessXml;  
		if @xstate=1   commit transaction ProcessXml;     

		if isnull(@vMessage,'')=''
		select @vMessage=isnull(error_message(),@vMessage)

	end catch

	if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
	begin
		print 'CheckSchema: @AuditFile='+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
		set @TimeStamp=getdate()
	end
	
	if isnull(@vMessage,'')<>''
	begin
		set @MessageRO='Verificare Schema XML'
		set @MessageEN='Check XML Schema'

		insert into #ActionLogError 
			(ActionId, Flag, ErrorName, ErrorInfo)
		select @ActionId, 2, iif(@Language='RO',@MessageRO,@MessageEN),left(@vMessage,2000)

		goto HasError
	end 
	
	if @Testing=1    
	select @XmlNoSchema=@XmlD406T
	else
	select @XmlNoSchema=@XmlD406

	--select @XmlNoSchema=iif(@Testing=1,@XmlD406T,@XmlD406)

	merge Saft.ReportArchive as d
	using (
		select RepDescription=@RepDescription, RepXml=@XmlNoSchema
		) as s on (d.CompanyId=@CompanyId 
					and d.ReportId=@StatementId and d.RepTypeExtId=@RepTypeExtId 
					and d.StartDate=@StartDate and d.EndDate=@EndDate)
	when matched 
		then update set RepDescription=s.RepDescription, TimeStamp=getdate(), RepXml=s.RepXml, UserId=@UserId
	when not matched by target
		then insert (SessionId, CompanyId, UserId, ReportId, RepVersionId, RepTypeId, RepTypeExtId, 
					StartDate, EndDate, RepDescription, TimeStamp, RepXml) 
			values (NewId(), @CompanyId, @UserId, @StatementId, @RepVersionId, @RepTypeId, @RepTypeExtId, 
					@StartDate, @EndDate, s.RepDescription, getdate(), s.RepXml);

	if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
	begin
		print 'Save to ReportArchive: '+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
		set @TimeStamp=getdate()
	end

	HasError:
	begin
		set @ErrorMessage=null
		set @WarningMessage=null
		set @vMessage=null
		set @InfoXml=null
		set @Flag=0

		delete #ReportStructure where StrCode='4.2'

		update r
		set DescriptionRO='Facturi',
			DescriptionEN='Invoices'
		from #ReportStructure r
		where StrCode='4.1'	

		select @InfoXml=(
			select b.Flag, 
				CheckName=a.ActionName+iif(isnull(b.ErrorName,'')='','',': '+b.ErrorName), 
				CheckInfo=isnull(nullif(b.ErrorInfo,''),'')
			from #ActionLogError b 
			join (
				select r.ActionId, ActionName=iif(@Language='RO',r.DescriptionRO, r.DescriptionEN)
				from #ReportStructure r
				union 
				select a.ActionId, ActionName=iif(@Language='RO',a.DescriptionRO, a.DescriptionEN)
				from Saft.UserAction a (nolock)
				where a.ActionId=@ActionId
				) a on a.ActionId=b.ActionId
			where isnull(b.ErrorName,'')<>''
		for xml path('Check'), root('root'))

		select @Flag=max(Flag)
		from #ActionLogError b

		select @ErrorMessage=string_agg(iif(@Language='RO',a.DescriptionRO,a.DescriptionEN)/*+': '+b.Error_msg*/,'; ')
		from Saft.UserAction a (nolock)
		join (
			select a.ActionId, Error_msg=string_agg(a.ErrorName,'; ')
			from #ActionLogError a
			where a.Flag=2
			group by a.ActionId
			) b on a.ActionId=b.ActionId

		select @WarningMessage=string_agg(iif(@Language='RO',a.DescriptionRO,a.DescriptionEN)/*+': '+b.Error_msg*/,'; ')
		from Saft.UserAction a (nolock)
		join (
			select a.ActionId, Error_msg=string_agg(a.ErrorName,'; ')
			from #ActionLogError a
			where a.Flag=1
			group by a.ActionId
			) b on a.ActionId=b.ActionId

		if isnull(@ErrorMessage,'')<>''
		select @vMessage=iif(@Language='RO','Eroare','Error')+':'+@ErrorMessage

		if isnull(@WarningMessage,'')<>''
		select @vMessage=iif(isnull(@vMessage,'')<>'',@vMessage+'| ','')
			+iif(@Language='RO','Atentionare','Warning')+':'+@WarningMessage
				
	end

	InsertLogs:
	begin
		if isnull(@ErrorMessage,'')<>''    goto EndOfProc
		
		set @TimeStamp=getdate()

		delete a
		from Saft.Log_AccountTurnOver a
		where a.CompanyId=@CompanyId
			and a.StartDate=@StartDate

		delete a
		from Saft.Log_PartnerAccountTurnOver a
		where a.CompanyId=@CompanyId
			and a.StartDate=@StartDate

		insert into Saft.Log_AccountTurnOver
			(CompanyId, ActionId, StartDate, SaftAccountCode, StandardAccountCode, 
			OpeningDebitBalance, OpeningCreditBalance, ClosingDebitBalance, ClosingCreditBalance)
		select @CompanyId, @ActionId, @StartDate, AccountID, StandardAccountID, 
			OpeningDebitBalance, OpeningCreditBalance, ClosingDebitBalance, ClosingCreditBalance 
		from #GeneralLedgerAccounts

		insert into Saft.Log_PartnerAccountTurnOver
			(CompanyId, ActionId, StartDate, SaftPartnerId, SaftAccountCode,  
			OpeningDebitBalance, OpeningCreditBalance, ClosingDebitBalance, ClosingCreditBalance)
		select @CompanyId, @ActionId, @StartDate, SaftPartnerId, AccountID, 
			OpeningDebitBalance, OpeningCreditBalance, ClosingDebitBalance, ClosingCreditBalance 
		from #PartnerAccount

		if @DeBug=99 and datediff(s,@TimeStamp,getdate())<>0
		begin
			print 'Insert Logs: '+convert(varchar(100), datediff(s,@TimeStamp,getdate()),121)           
			set @TimeStamp=getdate()
		end

	end

	EndOfProc:
	begin
		set @vMessage=isnull(@vMessage,'')

		SessionUpd:
		begin
			declare @ParamValue varchar(255), @TaskId int
			set @TaskId=78 /*Process XML*/
			select @ParamValue=concat_ws('|',@RepVersionId,@RepTypeId,@RepTypeExtId,@StartDate,@EndDate)
			
			delete UserSession where SessionId=@SessionId and TaskId=@TaskId

			insert into UserSession
				(SessionId, TaskId, ParamValue)
			select @SessionId, @TaskId, @ParamValue
		end

		set @Flag=isnull(@Flag,0)

		update Saft.UserActionLogHistory 
		set EndTime=getdate(), 
			Error_msg=@vMessage, 
			Flag=@Flag,
			InfoXml=@InfoXml
		where SessionId=@SessionId 
			and ActionId=@ActionId 
			and CompanyId=@CompanyId 
			and UserId=@UserId
		
		if isnull(@vMessage,'')<>''
		and @Flag<>0
		select @vMessage=iif(@Flag=1,iif(@Language='RO','Atentionare','Warning'),iif(@Language='RO','Eroare','Error'))
					+': '+@vMessage
					+'.| '+iif(@Language='RO','Info: Click pe numele sectiunii cu','Info: Click on the name of the section with')
					+' '+iif(@Flag=1,iif(@Language='RO','Atentionare','Warning'),iif(@Language='RO','Eroare','Error'))

		drop table if exists #ReportStructure
		drop table if exists #Company
		drop table if exists #GeneralLedgerAccounts
		drop table if exists #PartnerAccount
		drop table if exists #TaxTable
		drop table if exists #xTaxTable
		drop table if exists #AnalysisTypeTable
		drop table if exists #MovementTypeTable
		drop table if exists #Products
		drop table if exists #PhysicalStock
		drop table if exists #Owners
		drop table if exists #Assets
		drop table if exists #MeasuringUnit
		drop table if exists #GeneralLedgerEntries
		drop table if exists #xGeneralLedgerEntries
		drop table if exists #Invoice
		drop table if exists #Payment
		drop table if exists #AssetTransaction
		drop table if exists #InvoiceAccount
		drop table if exists #InvoiceTax
		drop table if exists #PaymentTax
		drop table if exists #Partners
		drop table if exists #ActionLogError

	end

	set nocount off
	set ansi_warnings on
end
go