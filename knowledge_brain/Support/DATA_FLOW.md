---
module: Support
last_updated: 2026-08-19
round: 1
---

# Support — Data Flows

## Flow 1: Submit a new enquiry ticket

```
User taps "New Enquiry" (EnquiryListScreen FAB/AppBar icon, enquiry_list_screen.dart:41,64)
  → Navigator.pushNamed(AppRouter.enquiryForm[, arguments: {'initial_type': ...}])
  → app_router.dart:275-282 reads args['initial_type'] → EnquiryFormScreen(initialType: ...)
  → EnquiryFormScreen.initState() (enquiry_form_screen.dart:49)
      if kTicketTypes.containsKey(initialType) → _selectedType = initialType
      else → _selectedType stays 'General' (NOT a kTicketTypes key — see RULE-SUPPORT-003)
  → user fills Subject + Message, optionally taps a type chip (_buildTypePicker)
  → user taps Submit → _submit() (enquiry_form_screen.dart:70)
      _formKey.currentState!.validate() — both fields required
      → EnquiryService.submitEnquiry(type: kTicketTypes[_selectedType] ?? 1, subject, content)
          (enquiry_service.dart:82)
      → ApiClient.post('support/create-ticket', data: {type, subject, content})
          (core/network/api_client.dart:53 → Dio POST, no field-level encryption:
           'support/*' absent from AppConfig.encryptedEndpoints)
      → response.data returned as Map
  → if response['success'] == true:
      ref.invalidate(enquiriesProvider)  → next EnquiryListScreen watch re-fetches
      _showSuccessSheet(message, data) → bottom sheet shows ticket id/subject/status/submitted-on
        from response['data'] (enquiry_form_screen.dart:453-456)
      sheet dismissed → Navigator.of(context).pop() closes the form (line 112)
  → else: AppToast.show(message, type: error)
  → any thrown exception: generic "Something went wrong" toast (no Failure-type mapping)
```

## Flow 2: Load and display the enquiry list

```
Navigation to /enquiry-list (from profile side-menu "Enquiry" item, profile_screen.dart:288-289,
  or return-navigation after submitting a ticket)
  → EnquiryListScreen.build (enquiry_list_screen.dart:17) calls ref.watch(enquiriesProvider)
  → enquiriesProvider (FutureProvider, enquiry_service.dart:187) fires unconditionally on first watch
      — comment: "Token is managed by ApiInterceptor — always fires when screen opens", no userProvider gate
  → EnquiryService.getEnquiries() (enquiry_service.dart:96)
      → ApiClient.post('support/list', data: {})  — auth via bearer token in interceptor, no body
      → defensive multi-shape parse (root list / data list / data.{tickets,enquiries,list,items,data,records})
      → maps each element through Enquiry.fromJson
      → any parse exception → caught, logged (kDebugMode only), returns [] (silent failure)
  → AsyncValue states:
      loading → CircularProgressIndicator
      error   → error icon + "Could not load enquiries" + Retry (ref.refresh(enquiriesProvider))
      data:
        [] → _buildEmpty (icon + "No Enquiries Yet" + CTA copy, no button — CTA is the FAB above)
        non-empty → RefreshIndicator + ListView.separated → _buildCard per Enquiry
            (status badge color/icon switch, createdAt, subject, type tag if present, ticket id if present)
```

## Flow 3: Contextual enquiry from another module (Auto/Custom Savings "Get Support")

```
sip/screens/manage_savings_screen.dart:228-239 "Get Support" tile
  → Navigator.pushNamed(AppRouter.enquiryForm, arguments: {'initial_type': 'Auto Savings'})
  → matches kTicketTypes key exactly → chip pre-selected correctly

sip/screens/manage_custom_savings_screen.dart:218-228 "Get Support" tile
  → Navigator.pushNamed(AppRouter.enquiryForm, arguments: {'initial_type': 'Custom SIP'})
  → 'Custom SIP' is NOT a kTicketTypes key → initState's containsKey check fails
  → _selectedType silently stays default 'General' → no chip visually selected
  → if user submits without tapping a chip, ticket posts as type: 1 ('Enquiry'),
    losing the "this is about Custom SIP" context the caller intended (RULE-SUPPORT-003/004)
```
