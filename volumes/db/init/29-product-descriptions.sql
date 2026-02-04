-- =============================================
-- Migration: Add English and Gujarati descriptions for all products
-- =============================================
-- Each description is ~100-150 characters, covering flavor profile and common uses.

BEGIN;

-- ============================================================
-- SPICES (48 products)
-- ============================================================

UPDATE products SET
    description = 'Classic Indian dried red chilli flakes with straightforward heat and rustic flavor. Versatile for tadkas, chutneys, and pickles.',
    description_gu = 'દેશી લાલ મરચાંના ટુકડા, સીધી તીખાશ અને ગામડિયા સ્વાદ. વઘાર, ચટણી અને અથાણાં માટે ઉત્તમ.'
WHERE name = 'Crushed Chilli (Local)';

UPDATE products SET
    description = 'Balanced chilli flakes with moderate heat and good color. Ideal for those who enjoy warmth without overwhelming spice.',
    description_gu = 'સંતુલિત તીખાશ અને સારો રંગ. જેમને વધારે તીખું ન ગમે તેમના માટે યોગ્ય.'
WHERE name = 'Crushed Chilli (Medium)';

UPDATE products SET
    description = 'Vibrant deep-red flakes prized for brilliant color and gentle, fruity heat. Perfect for tandoori marinades and gravies.',
    description_gu = 'ઘેરો લાલ રંગ અને હળવી ફળદાર તીખાશ. તંદૂરી મેરિનેડ અને ગ્રેવી માટે શ્રેષ્ઠ.'
WHERE name = 'Crushed Chilli (Kashmiri)';

UPDATE products SET
    description = 'Dried haldi fingers with deep golden hue and earthy aroma. Grind fresh for the purest turmeric powder.',
    description_gu = 'સૂકી હળદરની આખી લાકડી, ઘેરો સોનેરી રંગ અને માટીનો સુગંધ. તાજું દળવા માટે શ્રેષ્ઠ.'
WHERE name = 'Whole Turmeric';

UPDATE products SET
    description = 'Vibrant golden turmeric with warm, earthy flavor. The cornerstone of Indian cooking for curries, dals, and rice.',
    description_gu = 'સોનેરી રંગ અને ગરમ, માટીનો સ્વાદ. દાળ, શાક અને ભાતમાં જરૂરી મસાલો.'
WHERE name = 'Turmeric Powder';

UPDATE products SET
    description = 'Fragrant sabut dhania with warm, citrusy, slightly floral aroma. Foundation for homemade curry powders and pickling blends.',
    description_gu = 'સુગંધિત આખી ધાણી, ગરમ અને ખાટા-મીઠા સ્વાદ સાથે. ઘરે મસાલો અને અથાણું બનાવવા માટે જરૂરી.'
WHERE name = 'Whole Coriander Seeds';

UPDATE products SET
    description = 'Classic Gujarati blend of crushed coriander and cumin. The essential base seasoning for dals, sabzis, and everyday cooking.',
    description_gu = 'ગુજરાતી રસોઈનું મૂળ - ધાણાજીરું. દાળ, શાક અને રોજિંદા રસોઈમાં અનિવાર્ય.'
WHERE name = 'Crushed Coriander-Cumin';

UPDATE products SET
    description = 'Elevated dhana-jeera blend with additional warming spices for a more complex, aromatic profile.',
    description_gu = 'વધારાના ગરમ મસાલા સાથે સ્વાદિષ્ટ ધાણાજીરું. દાળ અને શાકમાં વધુ સ્વાદ માટે.'
WHERE name = 'Spiced Coriander-Cumin Mix';

UPDATE products SET
    description = 'Earthy, warm seeds with distinctive nutty aroma. Essential for tadkas, jeera rice, raitas, and spice blends.',
    description_gu = 'માટીનો, ગરમ સ્વાદ અને અખરોટ જેવી સુગંધ. વઘાર, જીરા ભાત અને રાયતા માટે જરૂરી.'
WHERE name = 'Cumin Seeds';

UPDATE products SET
    description = 'Earthy, warm, and slightly smoky ground cumin. Indispensable for curries, raitas, chaats, and lentil dishes.',
    description_gu = 'ગરમ અને હળવો ધુમાડિયો સ્વાદ. શાક, રાયતા, ચાટ અને દાળમાં અનિવાર્ય.'
WHERE name = 'Cumin Powder';

UPDATE products SET
    description = 'Sharp, pungent seeds that mellow into nutty warmth when tempered in hot oil. Essential for tadka and pickles.',
    description_gu = 'તીખા બીજ જે ગરમ તેલમાં વઘારતા મીઠા-ગરમ થાય છે. વઘાર અને અથાણાં માટે જરૂરી.'
WHERE name = 'Mustard Seeds';

UPDATE products SET
    description = 'Mild yellow split mustard with gentler, tangy heat. Ideal for pickles, achaar masalas, and lighter chutneys.',
    description_gu = 'હળવી પીળી ખમણી રાઈ, ટેન્ગી સ્વાદ સાથે. અથાણાં અને ચટણી માટે ઉત્તમ.'
WHERE name = 'Split Mustard Seeds (Yellow)';

UPDATE products SET
    description = 'Small, golden-amber seeds with pleasantly bitter, maple-like flavor. Essential in pickles, tadkas, and spice blends.',
    description_gu = 'નાના સોનેરી બીજ, હળવા કડવા અને મીઠા સ્વાદ સાથે. અથાણાં અને વઘારમાં જરૂરી.'
WHERE name = 'Fenugreek Seeds';

UPDATE products SET
    description = 'Tiny, ridged seeds with sharp thyme-like flavor and peppery bite. A digestive aid used in parathas and pakoras.',
    description_gu = 'નાના, ધારદાર બીજ, થાઈમ જેવો સ્વાદ. પરાઠા અને પકોડામાં વપરાય છે. પાચન માટે સારું.'
WHERE name = 'Carom Seeds (Ajwain)';

UPDATE products SET
    description = 'Sun-dried Garcinia indica with deep tangy-sour flavor. Signature souring agent in Gujarati kadhi and sol kadi.',
    description_gu = 'સૂર્ય સૂકવેલા કોકમ, ખાટા-ટેન્ગી સ્વાદ સાથે. ગુજરાતી કઢી અને સોલ કઢીમાં જરૂરી.'
WHERE name = 'Salted Kokum';

UPDATE products SET
    description = 'Dense, dried imli block with intense sour-sweet tang. Essential for tamarind chutney, sambar, rasam, and pani puri.',
    description_gu = 'ઘટ્ટ સૂકી આંબલી, ખાટી-મીઠી સ્વાદ સાથે. ચટણી, સાંભાર, રસમ અને પાણીપુરી માટે જરૂરી.'
WHERE name = 'Tamarind';

UPDATE products SET
    description = 'Pungent resin with strong onion-garlic aroma that mellows when cooked. Essential in dal tadkas and Jain cuisine.',
    description_gu = 'તીવ્ર સુગંધ જે રાંધતા મીઠી બને છે. દાળના વઘાર અને જૈન રસોઈમાં જરૂરી.'
WHERE name = 'Crushed Asafoetida';

UPDATE products SET
    description = 'Versatile dal-sabji masala with balanced warming spices. Earthy, mildly pungent, and aromatic for everyday cooking.',
    description_gu = 'સંતુલિત ગરમ મસાલો. દાળ અને શાક માટે રોજિંદા રસોઈનો મસાલો.'
WHERE name = 'Lentil & Veg Spice Mix';

UPDATE products SET
    description = 'Warm, aromatic blend of ginger, cardamom, cinnamon, and clove for perfect Indian masala chai.',
    description_gu = 'આદુ, એલચી, તજ અને લવિંગનું સુગંધિત મિશ્રણ. સ્વાદિષ્ટ ચા માટે.'
WHERE name = 'Tea Masala';

UPDATE products SET
    description = 'Sweet, aromatic seeds with mild licorice flavor. Used in meat curries and pickles. Loved as after-meal digestive.',
    description_gu = 'મીઠા, સુગંધિત બીજ. માંસના શાક અને અથાણામાં વપરાય. જમ્યા પછી પાચન માટે લોકપ્રિય.'
WHERE name = 'Fennel Seeds';

UPDATE products SET
    description = 'Premium small-grain fennel from Lucknow. Exceptional sweetness and delicate aroma for mukhwas and fine blends.',
    description_gu = 'લખનૌની પ્રીમિયમ નાની વરિયાળી. અસાધારણ મીઠાશ અને નાજુક સુગંધ. મુખવાસ માટે શ્રેષ્ઠ.'
WHERE name = 'Fennel Seeds (Lucknow)';

UPDATE products SET
    description = 'Crunchy roasted dhana dal with warm, citrusy, toasted flavor. A beloved Gujarati snack and mukhwas ingredient.',
    description_gu = 'ક્રન્ચી શેકેલી ધાણાદાળ, ગરમ અને ખાટી-મીઠી સ્વાદ. ગુજરાતી નાસ્તો અને મુખવાસ માટે પ્રિય.'
WHERE name = 'Roasted Split Coriander';

UPDATE products SET
    description = 'Clean, white hulled til with delicate nutty flavor that intensifies when toasted. Essential for til chikki and ladoo.',
    description_gu = 'સફેદ છાલેલા તલ, નાજુક અખરોટ જેવો સ્વાદ. તલની ચિક્કી અને લાડુ માટે જરૂરી.'
WHERE name = 'Sesame Seeds';

UPDATE products SET
    description = 'Nutty, earthy seeds with richer flavor than white sesame. Used in chutneys, ladoos, and til sweets.',
    description_gu = 'ઘેરા કાળા તલ, ગાઢો અખરોટ જેવો સ્વાદ. ચટણી, લાડુ અને તલની મીઠાઈમાં વપરાય.'
WHERE name = 'Black Sesame Seeds';

UPDATE products SET
    description = 'Traditional Gujarati condiment of roasted flaxseeds with chilli, salt, and spices. Enjoy with rotla and khichdi.',
    description_gu = 'ભૂંજેલી અળસીનો પરંપરાગત ગુજરાતી મસાલો. રોટલા અને ખીચડી સાથે માણો.'
WHERE name = 'Flaxseed Masala';

UPDATE products SET
    description = 'Mildly sweet, citrusy ground coriander with warm, nutty undertone. Foundational spice for curries and dals.',
    description_gu = 'હળવો મીઠો, ખાટો ધાણા પાવડર. શાક અને દાળનો મૂળ મસાલો.'
WHERE name = 'Coriander Powder';

UPDATE products SET
    description = 'Premium dehydrated whole garlic with robust, pungent aroma. Rehydrates quickly for curries and marinades.',
    description_gu = 'પ્રીમિયમ સૂકું લસણ, મજબૂત અને તીવ્ર સુગંધ. શાક અને મેરિનેડ માટે ઝડપથી તૈયાર થાય.'
WHERE name = 'Garlic';

UPDATE products SET
    description = 'Sun-dried raw mango slices with intense tangy sourness. Traditional base for authentic Gujarati aam ka achaar.',
    description_gu = 'સૂર્ય સૂકવેલી કાચી કેરીના ટુકડા. અસલ ગુજરાતી કેરીના અથાણાં માટે.'
WHERE name = 'Dried Mango Slices';

UPDATE products SET
    description = 'Tangy, fruity powder from sun-dried unripe mangoes. Adds bright sourness to chaats, chutneys, and marinades.',
    description_gu = 'કાચી કેરીનો ખાટો પાવડર. ચાટ, ચટણી અને મેરિનેડમાં ખાટાશ માટે.'
WHERE name = 'Dry Mango Powder (Amchur)';

UPDATE products SET
    description = 'Clean, white sabudana pearls that turn translucent when soaked. Fasting-day favorite for khichdi, vada, and kheer.',
    description_gu = 'સફેદ સાબુદાણા જે પલાળતા પારદર્શક થાય. ઉપવાસના ખીચડી, વડા અને ખીર માટે.'
WHERE name = 'Tapioca Pearls';

UPDATE products SET
    description = 'Ready-to-use spiced blend for traditional methi achaar. Mix with oil and lemon for instant pickle.',
    description_gu = 'મેથીના અથાણાં માટે તૈયાર મસાલો. તેલ અને લીંબુ સાથે મિક્સ કરો.'
WHERE name = 'Fenugreek Pickle Mix';

UPDATE products SET
    description = 'Ready-to-use achaar masala for sweet-style aam ka achaar. Mix with raw mango and oil for tangy-sweet pickle.',
    description_gu = 'ગોળકેરી અથાણાં માટે તૈયાર મસાલો. કાચી કેરી અને તેલ સાથે મિક્સ કરો.'
WHERE name = 'Sweet Mango Pickle Mix';

UPDATE products SET
    description = 'Coarsely split brown rai with sharper, more immediate pungency. Key ingredient in Gujarati and Rajasthani pickles.',
    description_gu = 'છૂટી કરેલી ભૂરી રાઈ, તીખો સ્વાદ. ગુજરાતી અને રાજસ્થાની અથાણાંમાં જરૂરી.'
WHERE name = 'Split Mustard Seeds';

UPDATE products SET
    description = 'Split methi seeds with distinctive bitter, maple-like aroma. Used in Gujarati pickles and special masala blends.',
    description_gu = 'છૂટા કરેલા મેથીના બીજ, કડવો અને મીઠો સ્વાદ. ગુજરાતી અથાણાંમાં વપરાય.'
WHERE name = 'Split Fenugreek Seeds';

UPDATE products SET
    description = 'Dhana dal split from whole coriander, with mild, citrusy, slightly sweet taste. Popular mukhwas ingredient.',
    description_gu = 'આખી ધાણીમાંથી છૂટી કરેલી દાળ, હળવી મીઠી. મુખવાસ માટે લોકપ્રિય.'
WHERE name = 'Split Coriander Seeds';

UPDATE products SET
    description = 'Fine, cream-colored khus khus with mild, nutty flavor. Used as thickener in rich Mughlai gravies and kormas.',
    description_gu = 'ક્રીમ રંગના ખસખસ, હળવો અખરોટ જેવો સ્વાદ. મુઘલાઈ ગ્રેવી અને કોરમામાં ઘટ્ટ કરવા માટે.'
WHERE name = 'Poppy Seeds';

UPDATE products SET
    description = 'The king of spices. Sharp, pungent whole peppercorns with woody aroma. Essential in marinades and rasam.',
    description_gu = 'મસાલાનો રાજા. તીખા, સુગંધિત કાળા મરી. મેરિનેડ અને રસમમાં જરૂરી.'
WHERE name = 'Black Pepper';

UPDATE products SET
    description = 'Intensely aromatic flower buds with warm, sweet, and slightly sharp flavor. Pillar of garam masala and biryanis.',
    description_gu = 'તીવ્ર સુગંધિત ફૂલની કળીઓ, ગરમ અને મીઠો સ્વાદ. ગરમ મસાલા અને બિરયાનીમાં મુખ્ય.'
WHERE name = 'Cloves';

UPDATE products SET
    description = 'Warm, sweet bark with comforting woody aroma. A staple in garam masala, biryanis, chai, and curries.',
    description_gu = 'ગરમ, મીઠી છાલ અને આરામદાયક સુગંધ. ગરમ મસાલા, બિરયાની અને ચામાં જરૂરી.'
WHERE name = 'Cinnamon';

UPDATE products SET
    description = 'Subtle herbal aroma with warm, slightly bitter notes. Essential for tempering rice dishes and slow-cooked curries.',
    description_gu = 'હળવી હર્બલ સુગંધ, ગરમ અને થોડો કડવો સ્વાદ. ભાત અને ધીમા પકવેલા શાકમાં જરૂરી.'
WHERE name = 'Bay Leaves';

UPDATE products SET
    description = 'Compact, round dried chillies with sharp, concentrated heat. Popular for tempering dals and making chutneys.',
    description_gu = 'ગોળ સૂકા મરચાં, તીવ્ર તીખાશ સાથે. દાળના વઘાર અને ચટણીમાં લોકપ્રિય.'
WHERE name = 'Dried Round Chillies';

UPDATE products SET
    description = 'Intensely aromatic pods with warm, sweet, and floral flavor. Prized in biryanis, chai, kheer, and mithai.',
    description_gu = 'તીવ્ર સુગંધિત દાણા, ગરમ અને મીઠો ફૂલ જેવો સ્વાદ. બિરયાની, ચા અને મીઠાઈમાં કિંમતી.'
WHERE name = 'Green Cardamom';

UPDATE products SET
    description = 'Warm, nutty spice with sweet, slightly woody aroma. Grate fresh into biryanis, chai, sweets, and garam masala.',
    description_gu = 'ગરમ, અખરોટ જેવો મસાલો. બિરયાની, ચા અને મીઠાઈમાં તાજું છીણો.'
WHERE name = 'Nutmeg';

UPDATE products SET
    description = 'Bold, smoky pods with intense camphor-like aroma. Prized in rich gravies, biryanis, and meat dishes.',
    description_gu = 'ધુમાડિયા સ્વાદના મોટા દાણા. ભારે ગ્રેવી, બિરયાની અને માંસના શાકમાં કિંમતી.'
WHERE name = 'Black Cardamom';

UPDATE products SET
    description = 'Beautiful star-shaped pods with sweet, warm, licorice-like aroma. Adds depth to biryanis and Chinese dishes.',
    description_gu = 'તારા આકારના સુંદર ફળ, મીઠી અને ગરમ સુગંધ. બિરયાની અને ચાઈનીઝ વાનગીઓમાં ઊંડાણ આપે.'
WHERE name = 'Star Anise';

UPDATE products SET
    description = 'Fragrant, slightly bitter leaves with unique maple-like aroma. Sprinkle into butter chicken, paneer, and naan.',
    description_gu = 'સુગંધિત, થોડા કડવા પાન. બટર ચિકન, પનીર અને નાનમાં છાંટો.'
WHERE name = 'Dried Fenugreek Leaves';

UPDATE products SET
    description = 'Delicate lacy covering of nutmeg with warm, subtly sweet aroma. Adds elegant depth to Mughlai curries and kormas.',
    description_gu = 'જાયફળનું નાજુક જાળું આવરણ, ગરમ અને મીઠી સુગંધ. મુઘલાઈ શાક અને કોરમામાં ભવ્યતા ઉમેરે.'
WHERE name = 'Mace';

UPDATE products SET
    description = 'Superior Ceylon-style cinnamon with delicate, layered bark and refined, mildly sweet flavor for premium dishes.',
    description_gu = 'ઉચ્ચ ગુણવત્તાની સિલોન-શૈલીની તજ, નાજુક સ્તરવાળી છાલ. ખાસ વાનગીઓ માટે.'
WHERE name = 'Cinnamon (Export)';

-- ============================================================
-- DRIED GOODS (6 products)
-- ============================================================

UPDATE products SET
    description = 'Large traditional papads made from premium rice flour. Roast or deep-fry for crispy accompaniment to any meal.',
    description_gu = 'ચોખાના લોટમાંથી બનેલા મોટા પાપડ. શેકો અથવા તળો, ભોજન સાથે ક્રિસ્પી સાઇડ ડિશ.'
WHERE name = 'Rice Papads';

UPDATE products SET
    description = 'Bite-sized mini rice papads, perfect for quick frying or roasting. Delightful accompaniment or light snack.',
    description_gu = 'નાના ડિસ્કો પાપડ, ઝડપથી તળવા અથવા શેકવા માટે. ભોજન સાથે અથવા નાસ્તા તરીકે.'
WHERE name = 'Small Rice Papads';

UPDATE products SET
    description = 'Fine, traditional wheat noodles for sweet and savory dishes. Make kheer, sheer khurma, or vegetable upma.',
    description_gu = 'પાતળી ઘઉંની સેવ, મીઠી અને ખારી વાનગીઓ માટે. ખીર, શીર ખુરમા અથવા ઉપમા બનાવો.'
WHERE name = 'Wheat Vermicelli';

UPDATE products SET
    description = 'Sun-dried potato slices ready to deep-fry into crispy golden chips. Perfect for tea-time and festive gatherings.',
    description_gu = 'સૂર્ય સૂકવેલી બટાકાની ચિપ્સ, તળવા માટે તૈયાર. ચા સમયે અને તહેવારોમાં ક્રિસ્પી નાસ્તો.'
WHERE name = 'Dried Potato Chips';

UPDATE products SET
    description = 'Net-patterned sun-dried potato wafers that fry into delicate, lacy crisps. Unique design with extra-light crunch.',
    description_gu = 'જાળીદાર સૂકવેલી બટાકાની ચિપ્સ, તળતા નાજુક અને હલકી. અનોખી ડિઝાઇન સાથે ક્રન્ચી.'
WHERE name = 'Potato Wafers (Netted)';

UPDATE products SET
    description = 'Thin-cut sun-dried potato sticks that fry into crunchy, golden sev. A beloved traditional snack.',
    description_gu = 'પાતળી સૂકવેલી બટાકાની સળી, તળતા સોનેરી અને ક્રન્ચી. પરંપરાગત પ્રિય નાસ્તો.'
WHERE name = 'Potato Sticks';

-- ============================================================
-- POWDERS (20 products)
-- ============================================================

UPDATE products SET
    description = 'Finely ground dried ginger with sharp, warming, and slightly sweet flavor. Used in chai, kadha, and sweets.',
    description_gu = 'ઝીણું દળેલું સૂંઠ, તીખું અને ગરમ, થોડું મીઠું. ચા, ઉકાળો અને મીઠાઈમાં વપરાય.'
WHERE name = 'Dry Ginger Powder';

UPDATE products SET
    description = 'Long pepper root powder with warm, earthy, mildly peppery taste. Revered Ayurvedic spice for herbal remedies.',
    description_gu = 'ગાંઠોડાનો પાવડર, ગરમ અને હળવો મરી જેવો સ્વાદ. આયુર્વેદિક ઉપચારમાં આદરણીય.'
WHERE name = 'Pipramul Root Powder';

UPDATE products SET
    description = 'Pure sodium bicarbonate, versatile leavening agent. Adds lightness to baked goods, batters, and dhokla.',
    description_gu = 'શુદ્ધ ખાવાનો સોડા. બેકડ વસ્તુઓ, બેટર અને ઢોકળામાં હલકાપણું આપે.'
WHERE name = 'Baking Soda';

UPDATE products SET
    description = 'Food-grade crystalline citric acid with clean, sharp sourness. Used in chutneys, preserves, and sherbets.',
    description_gu = 'ખાદ્ય-ગ્રેડ સિટ્રિક એસિડ, સ્વચ્છ અને તીખી ખાટાશ. ચટણી, મુરબ્બો અને શરબતમાં.'
WHERE name = 'Citric Acid';

UPDATE products SET
    description = 'Finely ground mineral-rich rock salt with mild, clean flavor. Preferred during fasting and for chaats.',
    description_gu = 'ઝીણું દળેલું ખનિજયુક્ત સિંધવ મીઠું. ઉપવાસ અને ચાટ માટે પસંદગી.'
WHERE name = 'Rock Salt Powder';

UPDATE products SET
    description = 'Distinctive smoky-sulphurous mineral salt with earthy, tangy flavor. Signature in chaat masala and jaljeera.',
    description_gu = 'ધુમાડિયું-ગંધકયુક્ત ખનિજ મીઠું, ખાટી-માટીનો સ્વાદ. ચાટ મસાલા અને જલજીરામાં ખાસ.'
WHERE name = 'Black Salt Powder';

UPDATE products SET
    description = 'Slightly bitter, maple-scented ground fenugreek. Adds complexity to curries, pickles, and spice blends.',
    description_gu = 'થોડો કડવો, મીઠી સુગંધવાળો મેથી પાવડર. શાક, અથાણાં અને મસાલામાં જટિલતા ઉમેરે.'
WHERE name = 'Fenugreek Powder';

UPDATE products SET
    description = 'Freshly ground black pepper with bold, pungent heat and sharp aroma. Essential for seasoning everything.',
    description_gu = 'તાજા દળેલા કાળા મરી, જોરદાર તીખાશ અને તીક્ષ્ણ સુગંધ. બધામાં સીઝનિંગ માટે જરૂરી.'
WHERE name = 'Black Pepper Powder';

UPDATE products SET
    description = 'Warm, sweet, and subtly woody ground cinnamon. Ideal for biryanis, desserts, chai masala, and baked goods.',
    description_gu = 'ગરમ, મીઠો અને હળવો લાકડાનો તજ પાવડર. બિરયાની, મીઠાઈ અને ચામાં આદર્શ.'
WHERE name = 'Cinnamon Powder';

UPDATE products SET
    description = 'Dehydrated tomato powder with concentrated, sweet-tangy umami flavor. Adds depth to gravies and sauces.',
    description_gu = 'સૂકવેલો ટમેટો પાવડર, ઘટ્ટ મીઠો-ખાટો ઉમામી સ્વાદ. ગ્રેવી અને સોસમાં ઊંડાણ ઉમેરે.'
WHERE name = 'Tomato Powder';

UPDATE products SET
    description = 'Tangy, sweet-sour ground tamarind with rich, fruity depth. Convenient for chutneys, sambar, and rasam.',
    description_gu = 'ખાટી-મીઠી આંબલી પાવડર, સમૃદ્ધ ફળનો સ્વાદ. ચટણી, સાંભાર અને રસમ માટે અનુકૂળ.'
WHERE name = 'Tamarind Powder';

UPDATE products SET
    description = 'Dehydrated lemon powder with bright, zesty tartness. Convenient for chaats, salads, and beverages.',
    description_gu = 'સૂકવેલો લીંબુ પાવડર, તેજ ખાટો સ્વાદ. ચાટ, સલાડ અને પીણાં માટે અનુકૂળ.'
WHERE name = 'Lemon Powder';

UPDATE products SET
    description = 'Natural dietary fiber with neutral taste. Supports digestive health. Also used in gluten-free baking.',
    description_gu = 'કુદરતી આહાર ફાઇબર, તટસ્થ સ્વાદ. પાચન સ્વાસ્થ્ય માટે સહાયક. ગ્લુટેન-ફ્રી બેકિંગમાં પણ.'
WHERE name = 'Psyllium Husk';

UPDATE products SET
    description = 'Crushed red pepper flakes with bright, lingering heat. Perfect for pizzas, pastas, and stir-fries.',
    description_gu = 'છૂંદેલા લાલ મરચાના ટુકડા, તેજ અને ટકાઉ તીખાશ. પિઝા, પાસ્તા અને સ્ટર-ફ્રાય માટે.'
WHERE name = 'Chilli Flakes';

UPDATE products SET
    description = 'Dried Mediterranean oregano with robust, slightly peppery herbaceous flavor. A must for Italian dishes.',
    description_gu = 'સૂકો મેડિટેરેનિયન ઓરેગાનો, મજબૂત હર્બલ સ્વાદ. ઇટાલિયન વાનગીઓ માટે જરૂરી.'
WHERE name = 'Oregano';

UPDATE products SET
    description = 'Finely ground dehydrated onion with concentrated sweetness and savory depth. Blends into spice rubs and gravies.',
    description_gu = 'ઝીણું દળેલું સૂકું ડુંગળી, ઘટ્ટ મીઠાશ અને સ્વાદ. મસાલા અને ગ્રેવીમાં ભળે.'
WHERE name = 'Onion Powder';

UPDATE products SET
    description = 'Finely ground dehydrated garlic with smooth, concentrated flavor. A pantry essential for rubs and marinades.',
    description_gu = 'ઝીણું દળેલું સૂકું લસણ, ઘટ્ટ સ્વાદ. રબ્સ અને મેરિનેડ માટે રસોડાનું જરૂરી.'
WHERE name = 'Garlic Powder';

UPDATE products SET
    description = 'Dehydrated onion pieces with sweet, savory flavor. Add to soups, gravies, and dry mixes for rich taste.',
    description_gu = 'સૂકા ડુંગળીના ટુકડા, મીઠો-સ્વાદિષ્ટ. સૂપ, ગ્રેવી અને ડ્રાય મિક્સમાં સમૃદ્ધ સ્વાદ માટે.'
WHERE name = 'Onion Flakes';

UPDATE products SET
    description = 'Dehydrated garlic slices with concentrated, savory-sweet flavor. Crush into dishes for convenient garlic punch.',
    description_gu = 'સૂકા લસણના ટુકડા, ઘટ્ટ સ્વાદ. વાનગીઓમાં છૂંદો લસણનો સ્વાદ માટે.'
WHERE name = 'Garlic Flakes';

UPDATE products SET
    description = 'Kashmiri-style chilli powder prized for brilliant red color and gentle warmth. Vibrant hue for tandoori dishes.',
    description_gu = 'કાશ્મીરી-શૈલીનો મરચું પાવડર, તેજ લાલ રંગ અને હળવી ગરમાશ. તંદૂરી વાનગીઓ માટે.'
WHERE name = 'Degi Chilli Powder';

-- ============================================================
-- SPICE MIXES (12 products)
-- ============================================================

UPDATE products SET
    description = 'Signature Kutchi-Gujarati blend balancing sweet, spicy, and tangy notes. Essential for authentic dabeli.',
    description_gu = 'કચ્છી-ગુજરાતી મિશ્રણ, મીઠો-તીખો-ખાટો સંતુલન. અસલ દાબેલી માટે જરૂરી.'
WHERE name = 'Dabeli Masala';

UPDATE products SET
    description = 'Zesty Gujarati blend of roasted cumin, black salt, and herbs. Adds refreshing tangy kick to buttermilk.',
    description_gu = 'ભૂંજેલા જીરા, સંચળ અને જડીબુટ્ટીનું ગુજરાતી મિશ્રણ. છાશમાં તાજગી આપે.'
WHERE name = 'Buttermilk Masala';

UPDATE products SET
    description = 'Robust, earthy blend for Punjabi-style chickpea curry. Deep, dark flavor that pairs perfectly with bhatura.',
    description_gu = 'પંજાબી-શૈલીના ચણા માટે મજબૂત મિશ્રણ. ભટૂરા સાથે યોગ્ય ઘેરો સ્વાદ.'
WHERE name = 'Chole Masala';

UPDATE products SET
    description = 'Vibrant, tangy-spicy blend for iconic Mumbai street food. Best with buttered pav.',
    description_gu = 'મુંબઈ સ્ટ્રીટ ફૂડ માટે તેજ ખાટો-તીખો મિશ્રણ. માખણવાળી પાવ સાથે શ્રેષ્ઠ.'
WHERE name = 'Pav Bhaji Masala';

UPDATE products SET
    description = 'Fragrant blend of whole and ground spices for authentic dum biryani. Rich, layered aroma.',
    description_gu = 'અસલ દમ બિરયાની માટે સુગંધિત આખા અને દળેલા મસાલાનું મિશ્રણ.'
WHERE name = 'Biryani Masala';

UPDATE products SET
    description = 'Lively mix of amchur, black salt, and cumin with bold tangy-spicy punch. Sprinkle over fruits and snacks.',
    description_gu = 'આંબોળિયા, સંચળ અને જીરાનું જીવંત મિશ્રણ. ફળ અને નાસ્તા પર છાંટો.'
WHERE name = 'Chaat Masala';

UPDATE products SET
    description = 'Traditional South Indian blend for lentil stew. Authentic tangy-spiced depth for sambar and rasam.',
    description_gu = 'દક્ષિણ ભારતીય દાળના સ્ટ્યુ માટે પરંપરાગત મિશ્રણ. સાંભાર અને રસમ માટે.'
WHERE name = 'Sambar Masala';

UPDATE products SET
    description = 'Versatile all-purpose masala for vegetables and paneer. Balanced, savory depth for any dish.',
    description_gu = 'શાકભાજી અને પનીર માટે બહુમુખી મસાલો. કોઈપણ વાનગી માટે સંતુલિત સ્વાદ.'
WHERE name = 'Kitchen King';

UPDATE products SET
    description = 'Fiery blend inspired by African-Portuguese cuisine. Bold heat and smoky tang for fries and grilled items.',
    description_gu = 'આફ્રિકન-પોર્ટુગીઝ રસોઈથી પ્રેરિત તીખું મિશ્રણ. ફ્રાઈઝ અને ગ્રિલ્ડ વસ્તુઓ માટે.'
WHERE name = 'Peri Peri';

UPDATE products SET
    description = 'Comforting blend of mild spices for classic rice-and-lentil dish. Gentle warmth for everyday khichdi.',
    description_gu = 'ચોખા-દાળની ક્લાસિક વાનગી માટે આરામદાયક મિશ્રણ. રોજિંદી ખીચડી માટે.'
WHERE name = 'Khichdi Masala';

UPDATE products SET
    description = 'Traditional Gujarati digestive powder of roasted cumin, pepper, and hing. Enjoy after meals or over dal.',
    description_gu = 'ભૂંજેલા જીરા, મરી અને હિંગનો પરંપરાગત ગુજરાતી પાચક પાવડર. ભોજન પછી માણો.'
WHERE name = 'Jiralu Powder';

UPDATE products SET
    description = 'Punchy, garlicky dry spice blend for Mumbai street snack. Dust over vada or mix into dry chutney.',
    description_gu = 'મુંબઈ સ્ટ્રીટ સ્નેક માટે લસણવાળો તીખો મિશ્રણ. વડા પર છાંટો અથવા સૂકી ચટણીમાં.'
WHERE name = 'Vadapav Masala';

COMMIT;

-- Verification query
-- SELECT name, LEFT(description, 50) as desc_en, LEFT(description_gu, 30) as desc_gu FROM products ORDER BY category_id, display_order;
