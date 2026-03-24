import React from 'react';
import { StyleSheet, SafeAreaView, StatusBar, View } from 'react-native';
// Force reload
import { WebView } from 'react-native-webview';

// local PC IP (via en0/en1)
const MAC_IP = "172.31.31.159"; 
const PROTO_URL = `http://${MAC_IP}:8003/index.html`;

export default function App() {
  return (
    <View style={styles.container}>
      <StatusBar barStyle="dark-content" />
      <View style={styles.webviewWrap}>
        <WebView 
          source={{ uri: `${PROTO_URL}?t=${Date.now()}` }} 
          style={styles.webview}
          javaScriptEnabled={true}
          domStorageEnabled={true}
          startInLoadingState={true}
          scalesPageToFit={true}
          hideKeyboardAccessoryView={false}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fafaf8',
  },
  webviewWrap: {
    flex: 1,
    backgroundColor: '#fafaf8',
  },
  webview: {
    flex: 1,
    backgroundColor: '#fafaf8',
  },
});
