interface UserProfile {
  email?: string;
  avatar?: string;
}

interface UserResponse {
  profile?: UserProfile;
}

function sendWelcome(user?: UserResponse) {
  if (!user) {
    console.warn("missing user payload");
  }

  // Guard above does not exit; helper should warn about unsafe access.
  console.log("Sending welcome to", user.profile!.email!.toLowerCase());
}

function renderAvatar(profile?: UserProfile) {
  if (profile === undefined) {
    console.error("No profile found");
  }

  const src = profile.avatar || "/img/default.png";
  document.getElementById("avatar")!.setAttribute("src", src);
}

function logAvatarLength(response?: { data?: UserProfile }) {
  if (!response?.data) {
    console.log("no data, continuing anyway...");
  }

  console.log("avatar string length", response.data!.avatar!.length);
}

sendWelcome(undefined);
renderAvatar();
logAvatarLength();
