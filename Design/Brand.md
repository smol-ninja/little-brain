# Wordmark

The displayed name is `littlebrain`, without a hyphen. The wordmark uses Neuropolitical Regular by Raymond Larabie, paired with the blue glass logo. Chat titles, counters, and controls keep the system font.

Three prototypes were compared at the panel's 360-point width in light and dark appearances:

| Direction | Result |
| --- | --- |
| Lowercase, one line | Selected. The name remains readable at 140 points wide and fits beside the counter. |
| Uppercase, one line | The wider letters require a smaller size in the same space. |
| Two lines | Fits easily but splits the name and gives the header more vertical emphasis. |

`Assets/Wordmark.pdf` is fixed vector artwork for the app. The two SVGs in `docs/` contain the same outlined lettering for GitHub's light and dark themes. They contain no font software, font references, or individually reusable character assets. The app uses the PDF as a template image so it follows the system text color and announces its name to VoiceOver.

The source is Neuropolitical Regular, PostScript name `Neuropolitical-Regular`, from Typodermic's official `typodermic-free-fonts-2026i.zip`, retrieved on 2026-10-26. Its included Desktop EULA v260817, sections 2.2 and 2.3, permit finished logos and outlined artwork without embedded font software. The OTF stays outside the repository and app bundle.

- [Typeface](https://typodermicfonts.com/neuropolitical-science/)
- [Official download and permitted uses](https://typodermicfonts.com/desktop/)
