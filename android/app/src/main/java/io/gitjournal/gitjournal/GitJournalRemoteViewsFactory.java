package io.gitjournal.gitjournal;

import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;
import android.widget.RemoteViewsService;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

import es.antonborri.home_widget.HomeWidgetPlugin;
import android.util.Log;
import android.net.Uri;

public class GitJournalRemoteViewsFactory implements RemoteViewsService.RemoteViewsFactory {
    private final Context context;
    private List<JSONObject> notes = new ArrayList<>();

    public GitJournalRemoteViewsFactory(Context context, Intent intent) {
        this.context = context;
    }

    @Override
    public void onCreate() {
        // Init
    }

    public void onDataSetChanged() {
        SharedPreferences prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE);
        String json = prefs.getString("notes_data", "[]");
        Log.d("GitJournalWidget", "onDataSetChanged: " + json);
        notes.clear();
        try {
            JSONArray array = new JSONArray(json);
            for (int i = 0; i < array.length(); i++) {
                notes.add(array.getJSONObject(i));
            }
        } catch (JSONException e) {
            e.printStackTrace();
        }
    }

    @Override
    public void onDestroy() {
        notes.clear();
    }

    @Override
    public int getCount() {
        return notes.size();
    }

    @Override
    public RemoteViews getViewAt(int position) {
        if (position >= notes.size()) return null;

        // Use widget_keep_item layout
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_keep_item);
        JSONObject note = notes.get(position);

        try {
            String title = note.optString("title", "Untitled");
            String body = note.optString("body", "");
            
            views.setTextViewText(R.id.note_title, title);
            views.setTextViewText(R.id.note_body, body);
            
            // Fill in the locking intent
            // Fill in the locking intent
            Intent fillInIntent = new Intent();
            fillInIntent.setData(Uri.parse("gitjournal://note?path=" + Uri.encode(note.optString("path"))));
            views.setOnClickFillInIntent(R.id.widget_item_root, fillInIntent);
        } catch (Exception e) {
            e.printStackTrace();
        }

        // We need to set the fillInIntent on SOMETHING.
        // Let's set it on the title and body for now as a fallback if I forget to update XML.
        // But the best is to update the XML.
        
        return views;
    }

    @Override
    public RemoteViews getLoadingView() {
        return null;
    }

    @Override
    public int getViewTypeCount() {
        return 1;
    }

    @Override
    public long getItemId(int position) {
        return position;
    }

    @Override
    public boolean hasStableIds() {
        return false;
    }
}
