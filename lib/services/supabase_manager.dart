import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseManager {
  static final SupabaseManager _instance = SupabaseManager._internal();
  late final SupabaseClient client;

  factory SupabaseManager() {
    return _instance;
  }

  SupabaseManager._internal() {
    client = SupabaseClient(
      'https://wpibdxrxpzkvgagtikue.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndwaWJkeHJ4cHprdmdhZ3Rpa3VlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mzg4MDE4MzksImV4cCI6MjA1NDM3NzgzOX0.-JIZeCEu6aJkW01X4HrdrMboFqnubkzebYaNj-WL7Z0', // Supabaseアノンキー
    );
  }
}

final supabase = SupabaseManager().client;
