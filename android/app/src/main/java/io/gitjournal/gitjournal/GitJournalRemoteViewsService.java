package io.gitjournal.gitjournal;

import android.content.Intent;
import android.widget.RemoteViewsService;

public class GitJournalRemoteViewsService extends RemoteViewsService {
    @Override
    public RemoteViewsFactory onGetViewFactory(Intent intent) {
        return new GitJournalRemoteViewsFactory(this.getApplicationContext(), intent);
    }
}
