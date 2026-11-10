/// D4: a coach list that is still being read has nothing to say yet.
///
/// The coach dashboard reads its lists with `.valueOrNull ?? []`. F-15 kept a
/// failed read apart from that empty list, but not a read still in flight, so
/// until the roster arrived a coach with clients was told "No clients found".
///
/// A reload that already holds rows keeps showing them (a realtime tick or a
/// token refresh re-reads the roster; it should not blank it). A reload holding
/// an EMPTY previous value is still reading: signing out leaves the roster at
/// `[]`, and the next coach to sign in would otherwise be told they have none.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

bool stillReading<T>(AsyncValue<List<T>> list) =>
    list.isLoading && (list.valueOrNull?.isEmpty ?? true);
