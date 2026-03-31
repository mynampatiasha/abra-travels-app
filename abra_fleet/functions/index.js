const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.createClient = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated",
    );
  }

  // Verify admin role
  const callerUid = context.auth.uid;
  const callerDoc = await admin.firestore()
      .collection("users").doc(callerUid).get();

  if (!callerDoc.exists || callerDoc.data().role !== "admin") {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Only admins can create clients",
    );
  }

  const {
    email, password, name, contactPerson,
    phone, address, gstNumber, panNumber,
  } = data;

  // Validate required fields
  if (!email || !password || !name ||
      !contactPerson || !phone || !address) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing required fields",
    );
  }

  try {
    // Create Firebase Auth user
    const userRecord = await admin.auth().createUser({
      email: email,
      password: password,
      displayName: contactPerson,
    });

    const userId = userRecord.uid;
    console.log(`✅ Auth user created: ${userId}`);

    // Create Firestore document
    await admin.firestore().collection("users").doc(userId).set({
      email: email,
      name: contactPerson,
      role: "client",
      companyName: name,
      phoneNumber: phone,
      address: address,
      gstNumber: gstNumber || null,
      panNumber: panNumber || null,
      authProvider: "email",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: callerUid,
      status: "active",
    });
    console.log(`✅ Firestore document created`);

    // Create Realtime Database entry
    const clientRef = admin.database().ref("clients").push();
    await clientRef.set({
      userId: userId,
      name: name,
      email: email,
      phone: phone,
      address: address,
      contactPerson: contactPerson,
      gstNumber: gstNumber || null,
      panNumber: panNumber || null,
      createdAt: new Date().toISOString(),
      createdBy: callerUid,
      status: "active",
      totalCustomers: 0,
      activeVehicles: 0,
    });
    console.log(`✅ RTDB entry created: ${clientRef.key}`);

    return {
      success: true,
      message: "Client created successfully",
      userId: userId,
      email: email,
    };
  } catch (error) {
    console.error("❌ Error creating client:", error);

    if (error.code === "auth/email-already-exists") {
      throw new functions.https.HttpsError(
          "already-exists",
          "Email already registered",
      );
    }

    throw new functions.https.HttpsError("internal", error.message);
  }
});
