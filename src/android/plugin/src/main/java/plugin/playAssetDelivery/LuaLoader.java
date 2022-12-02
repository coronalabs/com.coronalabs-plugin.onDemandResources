//
//  LuaLoader.java
//  TemplateApp
//
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

// This corresponds to the name of the Lua playAssetDelivery,
// e.g. [Lua] require "plugin.playAssetDelivery"
package plugin.playAssetDelivery;

import static android.app.Activity.RESULT_CANCELED;
import static android.app.Activity.RESULT_OK;

import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.util.Log;
import android.webkit.WebView;
import android.widget.Toast;

import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;
import com.ansca.corona.CoronaRuntimeTask;
import com.ansca.corona.permissions.PermissionState;
import com.ansca.corona.permissions.PermissionsServices;
import com.google.android.play.core.assetpacks.AssetLocation;
import com.google.android.play.core.assetpacks.AssetPackLocation;
import com.google.android.play.core.assetpacks.AssetPackManager;
import com.google.android.play.core.assetpacks.AssetPackManagerFactory;
import com.google.android.play.core.assetpacks.AssetPackState;
import com.google.android.play.core.assetpacks.AssetPackStateUpdateListener;
import com.google.android.play.core.assetpacks.model.AssetPackStatus;
import com.google.android.play.core.tasks.OnSuccessListener;
import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.LuaState;
import com.naef.jnlua.NamedJavaFunction;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;


@SuppressWarnings({"WeakerAccess", "unused"})
public class LuaLoader implements JavaFunction, CoronaRuntimeListener {
	/** Lua registry ID to the Lua function to be called when the ad request finishes. */
	private int fListener;
	private int tempListener;

	/** This corresponds to the event name, e.g. [Lua] event.name */
	private static final String Main_EVENT_NAME = "playAssetDeliveryEvent";
	private static final String Request_EVENT_NAME = "request";
	private int requestPackIdIndex = 1;
	private int requestForceDownloadIndex = 2;
	private int requestListenerIndex = 3;
	private boolean initSuccess = false;
	private boolean isRequestInProcess = false;
	private boolean waitForWifiConfirmationShown = false;
	private AssetPackManager assetPackManager;
//	private ArrayList<LuaState> requestsData = new ArrayList<LuaState>();

//	private ArrayList<LuaState> requestsData = new ArrayList<LuaState>();
	private List requestsData = new ArrayList<LuaState>();

	private List requestPackIds = new ArrayList<String>();
	private List requestListeners = new ArrayList<>();

	private ArrayList<List<String>> updatedRequestData = new ArrayList<>();



	private boolean initSuccessful() {
		return initSuccess;
	}

	/**
	 * Creates a new Lua interface to this plugin.
	 * <p>
	 * Note that a new LuaLoader instance will not be created for every CoronaActivity instance.
	 * That is, only one instance of this class will be created for the lifetime of the application process.
	 * This gives a plugin the option to do operations in the background while the CoronaActivity is destroyed.
	 */
	@SuppressWarnings("unused")
	public LuaLoader() {
		// Initialize member variables.
		fListener = CoronaLua.REFNIL;
		tempListener = CoronaLua.REFNIL;

		// Set up this plugin to listen for Corona runtime events to be received by methods
		// onLoaded(), onStarted(), onSuspended(), onResumed(), and onExiting().
		CoronaEnvironment.addRuntimeListener(this);
	}

	/**
	 * Called when this plugin is being loaded via the Lua require() function.
	 * <p>
	 * Note that this method will be called every time a new CoronaActivity has been launched.
	 * This means that you'll need to re-initialize this plugin here.
	 * <p>
	 * Warning! This method is not called on the main UI thread.
	 * @param L Reference to the Lua state that the require() function was called from.
	 * @return Returns the number of values that the require() function will return.
	 *         <p>
	 *         Expected to return 1, the playAssetDelivery that the require() function is loading.
	 */
	@Override
	public int invoke(LuaState L) {
		// Register this plugin into Lua with the following functions.
		NamedJavaFunction[] luaFunctions = new NamedJavaFunction[] {
			new InitWrapper(),
			new RequestWrapper(),
			new PathWrapper(),
		};
		String libName = L.toString( 1 );
		L.register(libName, luaFunctions);

		// Returning 1 indicates that the Lua require() function will return the above Lua playAssetDelivery.
		return 1;
	}

	/**
	 * Called after the Corona runtime has been created and just before executing the "main.lua" file.
	 * <p>
	 * Warning! This method is not called on the main thread.
	 * @param runtime Reference to the CoronaRuntime object that has just been loaded/initialized.
	 *                Provides a LuaState object that allows the application to extend the Lua API.
	 */
	@Override
	public void onLoaded(CoronaRuntime runtime) {
		// Note that this method will not be called the first time a Corona activity has been launched.
		// This is because this listener cannot be added to the CoronaEnvironment until after
		// this plugin has been required-in by Lua, which occurs after the onLoaded() event.
		// However, this method will be called when a 2nd Corona activity has been created.

	}

	/**
	 * Called just after the Corona runtime has executed the "main.lua" file.
	 * <p>
	 * Warning! This method is not called on the main thread.
	 * @param runtime Reference to the CoronaRuntime object that has just been started.
	 */
	@Override
	public void onStarted(CoronaRuntime runtime) {
	}

	/**
	 * Called just after the Corona runtime has been suspended which pauses all rendering, audio, timers,
	 * and other Corona related operations. This can happen when another Android activity (ie: window) has
	 * been displayed, when the screen has been powered off, or when the screen lock is shown.
	 * <p>
	 * Warning! This method is not called on the main thread.
	 * @param runtime Reference to the CoronaRuntime object that has just been suspended.
	 */
	@Override
	public void onSuspended(CoronaRuntime runtime) {
	}

	/**
	 * Called just after the Corona runtime has been resumed after a suspend.
	 * <p>
	 * Warning! This method is not called on the main thread.
	 * @param runtime Reference to the CoronaRuntime object that has just been resumed.
	 */
	@Override
	public void onResumed(CoronaRuntime runtime) {
	}

	/**
	 * Called just before the Corona runtime terminates.
	 * <p>
	 * This happens when the Corona activity is being destroyed which happens when the user presses the Back button
	 * on the activity, when the native.requestExit() method is called in Lua, or when the activity's finish()
	 * method is called. This does not mean that the application is exiting.
	 * <p>
	 * Warning! This method is not called on the main thread.
	 * @param runtime Reference to the CoronaRuntime object that is being terminated.
	 */
	@Override
	public void onExiting(CoronaRuntime runtime) {
		// Remove the Lua listener reference.
		CoronaLua.deleteRef( runtime.getLuaState(), fListener );
		CoronaLua.deleteRef( runtime.getLuaState(), tempListener );
		fListener = CoronaLua.REFNIL;
		tempListener = CoronaLua.REFNIL;
		assetPackManager.unregisterListener(assetPackStateUpdateListener);
	}

	/**
	 * Simple example on how to dispatch events to Lua. Note that events are dispatched with
	 * Runtime dispatcher. It ensures that Lua is accessed on it's thread to avoid race conditions
	 * @param message simple string to sent to Lua in 'message' field.
	 */
	@SuppressWarnings("unused")
	public void dispatchEvent(final String message) {
		CoronaEnvironment.getCoronaActivity().getRuntimeTaskDispatcher().send( new CoronaRuntimeTask() {
			@Override
			public void executeUsing(CoronaRuntime runtime) {
				LuaState L = runtime.getLuaState();

				CoronaLua.newEvent( L, Main_EVENT_NAME );

				L.pushString(message);
				L.setField(-2, "message");

				try {
					CoronaLua.dispatchEvent( L, fListener, 0 );
				} catch (Exception ignored) {
				}
			}
		} );
	}

	/**
	 * The following Lua function has been called:  playAssetDelivery.init( listener )
	 * <p>
	 * Warning! This method is not called on the main thread.
	 * @param L Reference to the Lua state that the Lua function was called from.
	 * @return Returns the number of values to be returned by the playAssetDelivery.init() function.
	 */
	@SuppressWarnings({"WeakerAccess", "SameReturnValue"})
	public int init(LuaState L) {
		int listenerIndex = 1;
		initSuccess = true;

		System.out.println("init called : ");

		if (assetPackManager == null) {
			assetPackManager = AssetPackManagerFactory.getInstance(CoronaEnvironment.getCoronaActivity().getApplicationContext());
			assetPackManager.registerListener(assetPackStateUpdateListener);
		}

		if ( CoronaLua.isListener( L, listenerIndex, Main_EVENT_NAME ) ) {
			fListener = CoronaLua.newRef( L, listenerIndex );
		}

//		ArrayList<List<String>> myArray = new ArrayList<>();
//		myArray.add(Arrays.asList("task1", "subTask1", "subTask2"));
//		myArray.add(Arrays.asList("task2", "subTask1"));

//		// get the task1 value
//		String task1 = myArray.get(0).get(0);

//		System.out.println("init called newData 3 : " + myArray);

		return 0;
	}

	/**
	 * The following Lua function has been called:  playAssetDelivery.path( word )
	 * <p>
	 * Warning! This method is not called on the main thread.
	 * @param L Reference to the Lua state that the Lua function was called from.
	 * @return Returns the number of values to be returned by the playAssetDelivery.path() function.
	 */
	public int path(LuaState L) {

		if (!initSuccessful()) {
			Log.w("Corona", "Please call init before trying to get path.");
			return 0;
		}

		String packId = L.checkString( 1 );
		if ( null == packId ) {
			packId = "nil";
		}

		String assetPath = L.checkString( 2 );
		if ( null == assetPath ) {
			assetPath = "nil";
		}

//		System.out.println("packId : "+packId);
//		System.out.println("assetId : "+assetPath);

		AssetLocation assetLocation = assetPackManager.getAssetLocation(packId, assetPath);

		System.out.println("path assetPath location : "+assetLocation);

		String assetPathLocation = "No Path Found";
		if (assetLocation != null) {
			assetPathLocation = assetLocation.path();
		}
		L.pushString( assetPathLocation );

		return 1;
	}


	/**
	 * The following Lua function has been called:  playAssetDelivery.request()
	 * <p>
	 * Warning! This method is not called on the main thread.
	 * @param L Reference to the Lua state that the Lua function was called from.
	 * @return Returns the number of values to be returned by the playAssetDelivery.request() function.
	 */
	@SuppressWarnings("WeakerAccess")
	public int request(LuaState L) {
		if (!initSuccessful()) {
			Log.w("Corona", "Please call init before trying to request.");
			return 0;
		}

		String packId = L.checkString( requestPackIdIndex );
		if ( null == packId ) {
			packId = "nil";
		}

		Boolean forceDownload = L.checkBoolean( requestForceDownloadIndex );
		if ( null == forceDownload ) {
			forceDownload = true;
		}

		String assetsPath = getAbsoluteAssetPath(packId, "");
		if (assetsPath == null && forceDownload == false) {
			HashMap<String, String> data = new LinkedHashMap<>();
			data.put("isError", "true");
			data.put("tag", packId);
			pushRequestCallBackWithLuaState(L, data);
		}else if (assetsPath == null && forceDownload == true) {
			addRequestInQueue(L, packId);
		}else if (assetsPath != null) {
			HashMap<String, String> data = new LinkedHashMap<>();
			data.put("isError", "false");
			data.put("tag", packId);
			pushRequestCallBackWithLuaState(L, data);
		}

		return 0;
	}

	/** Implements the playAssetDelivery.init() Lua function. */
	@SuppressWarnings("unused")
	private class InitWrapper implements NamedJavaFunction {
		/**
		 * Gets the name of the Lua function as it would appear in the Lua script.
		 * @return Returns the name of the custom Lua function.
		 */
		@Override
		public String getName() {
			return "init";
		}
		
		/**
		 * This method is called when the Lua function is called.
		 * <p>
		 * Warning! This method is not called on the main UI thread.
		 * @param L Reference to the Lua state.
		 *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
		 * @return Returns the number of values to be returned by the Lua function.
		 */
		@Override
		public int invoke(LuaState L) {
			return init(L);
		}
	}

	/** Implements the playAssetDelivery.request() Lua function. */
	@SuppressWarnings("unused")
	private class RequestWrapper implements NamedJavaFunction {
		/**
		 * Gets the name of the Lua function as it would appear in the Lua script.
		 * @return Returns the name of the custom Lua function.
		 */
		@Override
		public String getName() {
			return "request";
		}
		
		/**
		 * This method is called when the Lua function is called.
		 * <p>
		 * Warning! This method is not called on the main UI thread.
		 * @param L Reference to the Lua state.
		 *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
		 * @return Returns the number of values to be returned by the Lua function.
		 */
		@Override
		public int invoke(LuaState L) {
			return request(L);
		}
	}

	/** Implements the playAssetDelivery.path() Lua function. */
	@SuppressWarnings("unused")
	private class PathWrapper implements NamedJavaFunction {
		@Override
		public String getName() {
			return "path";
		}

		@Override
		public int invoke(LuaState L) {
			return path(L);
		}
	}

	private String getAbsoluteAssetPath(String assetPack, String relativeAssetPath) {
		AssetPackLocation assetPackPath = assetPackManager.getPackLocation(assetPack);

		if (assetPackPath == null) {
			// asset pack is not ready
			return null;
		}

		String assetsFolderPath = assetPackPath.assetsPath();
		String assetPath = new File(assetsFolderPath, relativeAssetPath).getAbsolutePath();
		return assetPath;
	}

	private void addRequestInQueue(LuaState L, String packId) {
		String assetPackPath = getAbsoluteAssetPath(packId, "");
		if (assetPackPath == null) {
			final String pId = L.checkString( 1 );
			final int listener = CoronaLua.isListener(L, requestListenerIndex, Request_EVENT_NAME) ? CoronaLua.newRef(L, requestListenerIndex) : CoronaLua.REFNIL;
			updatedRequestData.add(Arrays.asList(pId, String.valueOf(listener)));
			downloadNextRequest();
		}else{
			System.out.println("addRequestInQueue pack already downloaded : " + packId);
			HashMap<String, String> data = new LinkedHashMap<>();
			data.put("isError", "false");
			data.put("tag", packId);
			pushRequestCallBackWithLuaState(L, data);
		}
	}

	private void pushRequestCallBackWithLuaState(LuaState L, HashMap<String, String> data) {
		final int listener = CoronaLua.isListener(L, requestListenerIndex, Request_EVENT_NAME) ? CoronaLua.newRef(L, requestListenerIndex) : CoronaLua.REFNIL;
		CoronaEnvironment.getCoronaActivity().getRuntimeTaskDispatcher().send( new CoronaRuntimeTask() {
			@Override
			public void executeUsing(CoronaRuntime runtime) {
				LuaState newLuaParam = runtime.getLuaState();
				CoronaLua.newEvent(newLuaParam, Request_EVENT_NAME);
//				Sample values for pushing data to listener response
//				L.pushString("message text");
////			L.setField(-2, "message");
				for (Map.Entry<String,String> entry : data.entrySet()){
					if (entry.getValue() == "false"){
						newLuaParam.pushBoolean(false);
					}else if (entry.getValue() == "true") {
						newLuaParam.pushBoolean(true);
					}else {
						newLuaParam.pushString(entry.getValue());
					}
					newLuaParam.setField(-2, entry.getKey());
				}
				try {
					CoronaLua.dispatchEvent( newLuaParam, listener, 0 );
				} catch (Exception ignored) {
					System.out.println("pushRequestCallBackWithLuaState Exception while sending response back");
				}
			}
		} );

	}

	private void pushRequestCallbackWithRegisteredListener(HashMap<String, String> data) {
		CoronaEnvironment.getCoronaActivity().getRuntimeTaskDispatcher().send( new CoronaRuntimeTask() {
			@Override
			public void executeUsing(CoronaRuntime runtime) {
				LuaState newLuaParam = runtime.getLuaState();
				CoronaLua.newEvent(newLuaParam, Request_EVENT_NAME);
				for (Map.Entry<String,String> entry : data.entrySet()){
					if (entry.getValue() == "false"){
						newLuaParam.pushBoolean(false);
					}else if (entry.getValue() == "true") {
						newLuaParam.pushBoolean(true);
					}else {
						newLuaParam.pushString(entry.getValue());
					}
					newLuaParam.setField(-2, entry.getKey());
				}
				newLuaParam.pushString(Request_EVENT_NAME);
				newLuaParam.setField(-2, "name");
				try {
					System.out.println("pushRequestCallbackWithRegisteredListener dispatchEvent pushCallback : " + data);
					CoronaLua.dispatchEvent( newLuaParam, tempListener, 0 );
				} catch (Exception ignored) {
					System.out.println("pushRequestCallbackWithRegisteredListener Exception while sending response back");
				}
			}
		} );

	}

	private void downloadNextRequest() {
		if (!updatedRequestData.isEmpty()){
			String packId = (String) updatedRequestData.get(0).get(0);
			String listener = (String) updatedRequestData.get(0).get(1);
			int uListener = Integer.parseInt(listener);
			tempListener = uListener; 	// Change the tempListener according to the in process request
			String assetPackPath = getAbsoluteAssetPath(packId, "");
			if (assetPackPath == null) {
				if (isRequestInProcess == false) {
					isRequestInProcess = true;
					List<String> assetPackList = new ArrayList<>();
					assetPackList.add(packId);
					assetPackManager.fetch(assetPackList);
					System.out.println("downloadNextRequest pack downloading started : " + packId);
				}else{
					System.out.println("No need to start new request " + packId);
				}
			}else{
				System.out.println("downloadNextRequest pack already downloaded : " + packId);;
				HashMap<String, String> data = new LinkedHashMap<>();
				data.put("isError", "false");
				data.put("tag", packId);
				pushRequestCallbackWithRegisteredListener(data);
				updatedRequestData.remove(0); 	// remove request from queue it's already downloaded
			}
		}else {
			System.out.println("downloadNextRequest There is no current request in queue");
		}
	}

	private void addDelayAndCheckNext() {
		final Handler handler = new Handler(Looper.getMainLooper());
		handler.postDelayed(new Runnable() {
			@Override
			public void run() {
				updatedRequestData.remove(0); 	// remove request from queue it's completed
				isRequestInProcess = false;
				downloadNextRequest();
			}
		}, 100);
	}

	/**
	 * AssetPackStateUpdateListener that listens to multiple events while downlading
	 */
	AssetPackStateUpdateListener assetPackStateUpdateListener = new AssetPackStateUpdateListener() {
		@Override
		public void onStateUpdate(AssetPackState state) {
			String packId = state.name();
			switch (state.status()) {
				case AssetPackStatus.PENDING:
					System.out.println("AssetPackStateUpdateListener PENDING : ");
					break;
				case AssetPackStatus.DOWNLOADING:
					long downloaded = state.bytesDownloaded();
					long totalSize = state.totalBytesToDownload();
					double percent = 100.0 * downloaded / totalSize;
					System.out.println("AssetPackStateUpdateListener packName : " + packId);
					System.out.println("AssetPackStateUpdateListener DOWNLOADING : " + String.format("%.2f", percent));

					HashMap<String, String> downloadingData = new LinkedHashMap<>();
					downloadingData.put("tag", packId);
					downloadingData.put("phase", "downloading");
					downloadingData.put("progress", String.format("%.2f", percent));
					pushRequestCallbackWithRegisteredListener(downloadingData);
					break;
				case AssetPackStatus.TRANSFERRING:
					// 100% downloaded and assets are being transferred.
					// Notify user to wait until transfer is complete.
					System.out.println("AssetPackStateUpdateListener TRANSFERRING : ");
					break;
				case AssetPackStatus.COMPLETED:
					// Asset pack is ready to use. Start the Game/App.
					System.out.println("AssetPackStateUpdateListener Completed : ");

					HashMap<String, String> successData = new LinkedHashMap<>();
					successData.put("isError", "false");
					successData.put("tag", packId);
					pushRequestCallbackWithRegisteredListener(successData);
					addDelayAndCheckNext(); 		// Add some delay before moving to next request
					break;
				case AssetPackStatus.FAILED:
					// Request failed. Notify user.
					System.out.println("AssetPackStateUpdateListener Failed : " + String.valueOf(state.errorCode()));

					HashMap<String, String> errorData = new LinkedHashMap<>();
					errorData.put("isError", "true");
					errorData.put("tag", packId);
					errorData.put("errorCode", String.valueOf(state.errorCode()));
					pushRequestCallbackWithRegisteredListener(errorData);
					addDelayAndCheckNext(); 		// Add some delay before moving to next request
					break;
				case AssetPackStatus.CANCELED:
					// Request canceled. Notify user.
					System.out.println("AssetPackStateUpdateListener CANCELED : ");
					addDelayAndCheckNext(); 		// Add some delay before moving to next request
					break;
				case AssetPackStatus.WAITING_FOR_WIFI:
					System.out.println("AssetPackStateUpdateListener Waiting for Wifi : ");

					if (!waitForWifiConfirmationShown) {
						assetPackManager.showCellularDataConfirmation(CoronaEnvironment.getCoronaActivity())
								.addOnSuccessListener(new OnSuccessListener<Integer>() {
									@Override
									public void onSuccess(Integer resultCode) {
										if (resultCode == RESULT_OK) {
											Log.w("Corona", "Wifi popup accepted.");
											//// Not sure if we need to request again or old request continues
											//// Just to be sure make request again so everything works correctly.
											isRequestInProcess = false;
											downloadNextRequest(); // wifi accepted request again for asset pack
										} else if (resultCode == RESULT_CANCELED) {
											Log.w("Corona", "Wifi popup denied.");
										}
									}
								});
						waitForWifiConfirmationShown = true;
						Log.w("Corona", "Please turn wifi on to download assets.");
					}

					HashMap<String, String> wifiData = new LinkedHashMap<>();
					wifiData.put("tag", packId);
					wifiData.put("phase", "waiting_for_wifi");
					pushRequestCallbackWithRegisteredListener(wifiData);

					break;
				case AssetPackStatus.NOT_INSTALLED:
					// Asset pack is not downloaded yet.
					System.out.println("AssetPackStateUpdateListener NOT_INSTALLED : ");
					break;
				case AssetPackStatus.UNKNOWN:
					// The Asset pack state is unknown
					System.out.println("AssetPackStateUpdateListener UNKNOWN : ");
					break;
			}
		}
	};

}
