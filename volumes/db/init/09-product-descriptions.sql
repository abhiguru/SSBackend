-- =============================================
-- Migration: Add descriptions for all products
-- =============================================
-- Each description is max 250 characters, covering
-- what the product is, its flavor profile, and common uses.

UPDATE products SET description = CASE name

  -- =============================================
  -- SPICES (44 products)
  -- =============================================

  WHEN 'Bay Leaves'
    THEN 'Aromatic dried leaves with a warm, herbal fragrance. Essential for tempering dals, biryanis, pulaos, and slow-cooked curries. Adds subtle depth to rice dishes and meat preparations.'

  WHEN 'Black Cardamom'
    THEN 'Bold, smoky pods with an intense camphor-like aroma. Prized in rich gravies, biryanis, and garam masala blends. Adds deep, earthy warmth to meat curries and festive rice dishes.'

  WHEN 'Black Pepper'
    THEN 'The king of spices. Sharp, pungent whole peppercorns with a woody aroma. Essential in seasoning blends, marinades, soups, and rasam. Crush fresh for maximum flavor.'

  WHEN 'Black Sesame Seeds'
    THEN 'Nutty, earthy seeds with a richer flavor than white sesame. Used in chutneys, ladoos, and til sweets. Excellent as a garnish for naan, salads, and stir-fries.'

  WHEN 'Carom Seeds (Ajwain)'
    THEN 'Tiny, ridged seeds with a sharp thyme-like flavor and peppery bite. A digestive aid used in parathas, pakoras, and dal tadkas. A little goes a long way.'

  WHEN 'Cinnamon'
    THEN 'Warm, sweet bark with a comforting woody aroma. A staple in garam masala, biryanis, chai, and curries. Adds gentle sweetness to both savory dishes and desserts.'

  WHEN 'Cinnamon (Export)'
    THEN 'Superior Ceylon-style cinnamon with delicate, layered bark and a refined, mildly sweet flavor. Ideal for premium spice blends, rich pulaos, and desserts.'

  WHEN 'Cloves'
    THEN 'Intensely aromatic flower buds with a warm, sweet, and slightly sharp flavor. A pillar of garam masala, biryanis, and chai. Used in marinades and rice dishes.'

  WHEN 'Crushed Asafoetida'
    THEN 'Pungent resin with a strong onion-garlic aroma that mellows into savory umami when cooked. Essential in dal tadkas, sambar, and Jain cuisine. A pinch transforms any dish.'

  WHEN 'Crushed Chilli (Kashmiri)'
    THEN 'Vibrant deep-red flakes prized for brilliant color and gentle, fruity heat. Perfect for curries, tandoori marinades, and gravies where rich color matters more than spice.'

  WHEN 'Crushed Chilli (Local)'
    THEN 'Classic Indian dried red chilli flakes with straightforward heat and rustic flavor. A versatile everyday spice for tadkas, chutneys, pickles, and general seasoning.'

  WHEN 'Crushed Chilli (Medium)'
    THEN 'Balanced chilli flakes offering moderate heat with good flavor depth. Ideal for those who enjoy warmth without overwhelming spice. Great in curries, stir-fries, and marinades.'

  WHEN 'Crushed Coriander-Cumin'
    THEN 'A classic Gujarati blend of crushed coriander and cumin in perfect proportion. The essential base seasoning for dals, sabzis, and everyday Indian cooking.'

  WHEN 'Cumin Seeds'
    THEN 'Earthy, warm seeds with a distinctive nutty aroma. The backbone of Indian cooking, essential for tadkas, jeera rice, raitas, and spice blends. Dry-roast for best flavor.'

  WHEN 'Dried Fenugreek Leaves'
    THEN 'Fragrant, slightly bitter leaves with a unique maple-like aroma. Crush and sprinkle into butter chicken, paneer dishes, and naan dough for an authentic finishing touch.'

  WHEN 'Dried Mango Slices'
    THEN 'Sun-dried raw mango slices with intense tangy sourness. The traditional base for authentic Gujarati and Rajasthani aam ka achaar. Ready to use in homemade pickle preparations.'

  WHEN 'Dried Round Chillies'
    THEN 'Compact, round dried chillies with sharp, concentrated heat. Popular in Gujarati and Rajasthani cuisine for tempering dals and chutneys. Adds rustic flavor and a fiery punch.'

  WHEN 'Dry Mango Powder (Amchur)'
    THEN 'Tangy, fruity powder from sun-dried unripe mangoes. Adds bright sourness to chaats, chutneys, marinades, and vegetable dishes. A citrus-free way to add acidity to any recipe.'

  WHEN 'Fennel Seeds'
    THEN 'Sweet, aromatic seeds with a mild licorice flavor. Used in panch phoron, meat curries, and pickles. Equally loved as an after-meal digestive with a refreshing, cooling note.'

  WHEN 'Fennel Seeds (Lucknow)'
    THEN 'Premium small-grain fennel from Lucknow, prized for exceptional sweetness and delicate aroma. The preferred choice for mukhwas, fine spice blends, and desserts.'

  WHEN 'Fenugreek Pickle Mix'
    THEN 'A ready-to-use spiced blend built around fenugreek seeds for traditional methi achaar. Aromatic, tangy, and perfectly balanced. Mix with oil and lemon for instant pickle.'

  WHEN 'Fenugreek Seeds'
    THEN 'Small, golden-amber seeds with a pleasantly bitter, maple-like flavor. Essential in pickles, tadkas, and spice blends. A staple in South and West Indian cooking.'

  WHEN 'Flaxseed Masala'
    THEN 'Traditional Gujarati condiment of roasted flaxseeds blended with chilli, salt, and spices. Nutty, savory, and mildly spicy. Enjoy with rotla, khichdi, or sprinkle over dal.'

  WHEN 'Garlic'
    THEN 'Premium dehydrated whole garlic with robust, pungent aroma and bold flavor. Rehydrates quickly in cooking. Ideal for curries, tadkas, marinades, and chutneys.'

  WHEN 'Green Cardamom'
    THEN 'Aromatic pods with a warm, sweet, and floral flavor. Prized in biryanis, chai, kheer, and mithai. Adds fragrant depth to both savory dishes and desserts.'

  WHEN 'Lentil & Veg Spice Mix'
    THEN 'A versatile dal-sabji masala with a balanced blend of warming spices. Earthy, mildly pungent, and aromatic. Stir into everyday dals, mixed vegetable curries, and sabzis.'

  WHEN 'Mace'
    THEN 'Javitri, the delicate lacy covering of nutmeg, with a warm, subtly sweet aroma. Adds elegant depth to Mughlai curries, kormas, biryanis, and desserts.'

  WHEN 'Mustard Seeds'
    THEN 'Bold black-brown seeds with a sharp, pungent bite that mellows into nutty warmth when tempered in hot oil. Essential for tadka, South Indian curries, and pickles.'

  WHEN 'Nutmeg'
    THEN 'Whole jaiphal with a warm, sweet, and slightly woody aroma. Grate fresh into biryanis, chai, sweets, and garam masala. A little goes a long way in adding aromatic warmth.'

  WHEN 'Poppy Seeds'
    THEN 'Fine, cream-colored khus khus seeds with a mild, nutty flavor. Used as a thickener in rich Mughlai gravies and kormas, and as a topping for naan and baked goods.'

  WHEN 'Roasted Split Coriander'
    THEN 'Crunchy roasted dhana dal with a warm, citrusy, toasted flavor. A beloved Gujarati snack on its own or in mukhwas. Also pairs well as a garnish over chaats and salads.'

  WHEN 'Salted Kokum'
    THEN 'Sun-dried Garcinia indica preserved in salt with a deep tangy-sour flavor. A signature souring agent in Gujarati kadhi, sol kadi, and Konkani fish curries.'

  WHEN 'Sesame Seeds'
    THEN 'Clean, white hulled til seeds with a delicate nutty flavor that intensifies when toasted. Essential for til chikki, ladoo, and dry chutneys. Adds subtle crunch to breads.'

  WHEN 'Spiced Coriander-Cumin Mix'
    THEN 'An elevated dhana-jeera blend enriched with additional warming spices for a more complex, aromatic profile. Stir into dals, curries, raita, and buttermilk for instant depth.'

  WHEN 'Split Coriander Seeds'
    THEN 'Dhana dal split from whole coriander, with a mild, citrusy, slightly sweet taste. A popular mukhwas ingredient and light snack. Also used in dry chutneys and spice blends.'

  WHEN 'Split Fenugreek Seeds'
    THEN 'Split methi seeds with a distinctive bitter, maple-like aroma. Used in Gujarati pickles, special masala blends, and traditional remedies. Adds unique depth to achaar mixes.'

  WHEN 'Split Mustard Seeds'
    THEN 'Coarsely split brown rai with sharper, more immediate pungency than whole seeds. A key ingredient in Gujarati and Rajasthani pickles, chutneys, and spice pastes.'

  WHEN 'Split Mustard Seeds (Yellow)'
    THEN 'Mild yellow split mustard with gentler, tangy heat perfect for pickles and achaar masalas. Their softer bite and bright color make them ideal for lighter chutneys and preserves.'

  WHEN 'Star Anise'
    THEN 'Beautiful star-shaped pods with a sweet, warm, licorice-like aroma. Adds fragrant depth to biryanis, slow-cooked curries, and chai. Grind into garam masala for aromatic finish.'

  WHEN 'Sweet Mango Pickle Mix'
    THEN 'Ready-to-use achaar masala blend for sweet-style aam ka achaar. Combines warming spices with a hint of sweetness. Mix with raw mango and oil for tangy-sweet homemade pickle.'

  WHEN 'Tamarind'
    THEN 'Dense, dried imli block with an intense sour-sweet tang. The essential base for tamarind chutney, sambar, rasam, and pani puri water. Soak and strain for rich pulp.'

  WHEN 'Tapioca Pearls'
    THEN 'Clean, white sabudana pearls that turn translucent and chewy when soaked. A fasting-day favorite for khichdi, vada, and kheer. High in energy and easy to digest.'

  WHEN 'Whole Coriander Seeds'
    THEN 'Fragrant sabut dhania with a warm, citrusy, slightly floral aroma. A foundational spice for homemade curry powders, dhana-jeera, and pickling blends. Roast and grind fresh.'

  WHEN 'Whole Turmeric'
    THEN 'Dried haldi fingers with a deep golden hue, earthy aroma, and warm, slightly bitter flavor. Grind fresh for the purest turmeric powder. Used in pickling and traditional remedies.'

  -- =============================================
  -- SPICE MIXES (13 products)
  -- =============================================

  WHEN 'Biryani Masala'
    THEN 'A fragrant blend of whole and ground spices including bay leaf, mace, and cardamom. Delivers the rich, layered aroma essential to authentic dum biryani preparations.'

  WHEN 'Buttermilk Masala'
    THEN 'A zesty Gujarati blend of roasted cumin, black salt, and dried herbs. Adds a refreshing tangy kick to chilled buttermilk. Ideal for making traditional masala chaas.'

  WHEN 'Chaat Masala'
    THEN 'A lively mix of amchur, black salt, and cumin with a bold tangy-spicy punch. Sprinkle over fruit, salads, or street-food favorites like pani puri and bhel.'

  WHEN 'Chole Masala'
    THEN 'A robust, earthy blend of coriander, pomegranate seed powder, and warming spices. Delivers the deep, dark flavor of Punjabi-style chickpea curry. Pairs perfectly with bhatura.'

  WHEN 'Dabeli Masala'
    THEN 'A signature Kutchi-Gujarati blend balancing sweet, spicy, and tangy notes with dried coconut and chilli powders. The essential seasoning for crafting authentic dabeli.'

  WHEN 'Jiralu Powder'
    THEN 'A traditional Gujarati digestive powder of roasted cumin, black pepper, and hing. Offers warm, earthy flavor that aids digestion. Enjoy after meals or sprinkle over dal and rice.'

  WHEN 'Khichdi Masala'
    THEN 'A comforting blend of turmeric, cumin, and mild whole spices for the classic rice-and-lentil dish. Adds gentle warmth and aroma to everyday khichdi and light dal preparations.'

  WHEN 'Kitchen King'
    THEN 'A versatile all-purpose masala combining coriander, fenugreek, turmeric, and aromatic spices. Enhances any vegetable, paneer, or dal dish with balanced, savory depth of flavor.'

  WHEN 'Pav Bhaji Masala'
    THEN 'A vibrant, tangy-spicy blend featuring Kashmiri chilli, coriander, and amchur. Recreate the iconic Mumbai street-food flavor in your mixed-vegetable bhaji. Best with buttered pav.'

  WHEN 'Peri Peri'
    THEN 'A fiery blend inspired by African-Portuguese cuisine with bird''s eye chilli, paprika, garlic, and citrus notes. Adds bold heat and smoky tang to fries, grilled veggies, and snacks.'

  WHEN 'Sambar Masala'
    THEN 'A traditional South Indian blend of roasted lentils, red chilli, fenugreek, and curry leaves. Imparts authentic tangy-spiced depth to sambar, rasam, and lentil-vegetable stews.'

  WHEN 'Tea Masala'
    THEN 'A warm, aromatic blend of ginger, cardamom, cinnamon, and clove crafted for Indian masala chai. Add a pinch to your brewing tea for a fragrant, soul-warming cup every time.'

  WHEN 'Vadapav Masala'
    THEN 'A punchy, garlicky dry spice blend with red chilli, mustard, and hing. Captures the bold flavor of Mumbai''s beloved street snack. Dust over vada or mix into dry chutney.'

  -- =============================================
  -- POWDERS (23 products)
  -- =============================================

  WHEN 'Baking Soda'
    THEN 'Pure sodium bicarbonate, a versatile leavening agent. Adds lightness to baked goods, batters, and dhokla. Also used as a tenderizer in marinades and for quick-rising doughs.'

  WHEN 'Black Pepper Powder'
    THEN 'Freshly ground black pepper with bold, pungent heat and sharp aroma. The king of spices, essential for seasoning curries, soups, marinades, and everyday cooking.'

  WHEN 'Black Salt Powder'
    THEN 'Distinctive smoky-sulphurous mineral salt with an earthy, tangy flavor. A signature ingredient in chaat masala, raitas, chutneys, and refreshing jaljeera drinks.'

  WHEN 'Chilli Flakes'
    THEN 'Crushed red pepper flakes with bright, lingering heat and rustic texture. Perfect for sprinkling on pizzas, pastas, stir-fries, and adding a fiery kick to marinades and dressings.'

  WHEN 'Cinnamon Powder'
    THEN 'Warm, sweet, and subtly woody ground cinnamon with a fragrant aroma. Ideal for biryanis, desserts, chai masala, curries, and baked goods. A versatile pantry staple.'

  WHEN 'Citric Acid'
    THEN 'Food-grade crystalline citric acid with a clean, sharp sourness. Used to add tangy brightness to chutneys, preserves, sherbets, and homemade spice blends.'

  WHEN 'Coriander Powder'
    THEN 'Mildly sweet, citrusy ground coriander with a warm, nutty undertone. A foundational spice in Indian cooking, essential for curries, dals, chutneys, and spice blends.'

  WHEN 'Cumin Powder'
    THEN 'Earthy, warm, and slightly smoky ground cumin with a deep aroma. Indispensable in Indian cuisine for seasoning curries, raitas, chaats, and lentil dishes.'

  WHEN 'Degi Chilli Powder'
    THEN 'Kashmiri-style chilli powder prized for its brilliant red color and gentle warmth. Adds vibrant hue to tandoori dishes, curries, and gravies without overpowering heat.'

  WHEN 'Dry Ginger Powder'
    THEN 'Finely ground dried ginger with a sharp, warming, and slightly sweet flavor. Widely used in chai, kadha, sweets, and Ayurvedic remedies for digestion and immunity.'

  WHEN 'Fenugreek Powder'
    THEN 'Slightly bitter, maple-scented ground fenugreek with earthy depth. Adds complexity to curries, pickles, and spice blends. Valued in traditional wellness practices.'

  WHEN 'Garlic Flakes'
    THEN 'Dehydrated garlic slices with concentrated, savory-sweet flavor. Rehydrate in cooking or crush into dishes for a convenient garlic punch in soups, stir-fries, and seasonings.'

  WHEN 'Garlic Powder'
    THEN 'Finely ground dehydrated garlic with smooth, concentrated flavor and pungent aroma. A pantry essential for rubs, marinades, sauces, bread seasoning, and everyday cooking.'

  WHEN 'Lemon Powder'
    THEN 'Dehydrated lemon powder with bright, zesty tartness. A convenient seasoning for chaats, salads, rice dishes, beverages, and dry rubs where fresh lemon is impractical.'

  WHEN 'Onion Flakes'
    THEN 'Dehydrated onion pieces with sweet, savory flavor that intensifies when cooked. Add to soups, gravies, stuffings, and dry mixes for rich onion taste with long shelf life.'

  WHEN 'Onion Powder'
    THEN 'Finely ground dehydrated onion with concentrated sweetness and savory depth. Blends seamlessly into spice rubs, marinades, gravies, dips, and seasoning mixes.'

  WHEN 'Oregano'
    THEN 'Dried Mediterranean oregano with a robust, slightly peppery herbaceous flavor. A must-have for pizzas, pastas, garlic bread, salads, and Italian-inspired seasonings.'

  WHEN 'Pipramul Root Powder'
    THEN 'Long pepper root powder with a warm, earthy, mildly peppery taste. A revered Ayurvedic spice used in traditional remedies, herbal formulations, and warming spice blends.'

  WHEN 'Psyllium Husk'
    THEN 'Natural dietary fiber with a neutral taste and smooth texture. Supports digestive health and regularity. Also used as a binding agent in gluten-free baking and dough preparation.'

  WHEN 'Rock Salt Powder'
    THEN 'Finely ground mineral-rich rock salt with a mild, clean flavor. Preferred during fasting rituals, and ideal for chaats, raitas, fruit seasoning, and everyday cooking.'

  WHEN 'Tamarind Powder'
    THEN 'Tangy, sweet-sour ground tamarind with rich, fruity depth. A convenient alternative to tamarind pulp for chutneys, sambar, rasam, and South Indian dishes.'

  WHEN 'Tomato Powder'
    THEN 'Dehydrated tomato powder with concentrated, sweet-tangy umami flavor. Adds rich tomato depth to gravies, soups, sauces, dry rubs, and instant spice mixes.'

  WHEN 'Turmeric Powder'
    THEN 'Vibrant golden turmeric with warm, earthy flavor and mild peppery note. The cornerstone of Indian cooking, essential for curries, dals, rice, and wellness remedies.'

  -- =============================================
  -- DRIED GOODS (6 products)
  -- =============================================

  WHEN 'Dried Potato Chips'
    THEN 'Sun-dried potato slices ready to deep-fry into crispy golden chips. These traditional snacks puff up beautifully when fried. Perfect for tea-time munching or festive gatherings.'

  WHEN 'Potato Sticks'
    THEN 'Thin-cut sun-dried potato sticks that fry into crunchy, golden sev in minutes. A beloved traditional snack with a satisfying crunch. Ideal for tea-time or as a chaat topping.'

  WHEN 'Potato Wafers (Netted)'
    THEN 'Net-patterned sun-dried potato wafers that fry into delicate, lacy crisps. Their unique lattice design gives extra-light crunch. A stunning snack for parties and tea-time.'

  WHEN 'Rice Papads'
    THEN 'Large traditional papads made from premium rice flour. Roast or deep-fry for a light, crispy accompaniment to any Indian meal. A perfect side dish for dal-rice or thali spreads.'

  WHEN 'Small Rice Papads'
    THEN 'Bite-sized mini rice papads, perfect for quick frying or roasting. These petite, crispy rounds make a delightful accompaniment to meals or a light snack on their own.'

  WHEN 'Wheat Vermicelli'
    THEN 'Fine, traditional wheat noodles for both sweet and savory dishes. Make creamy sheer khurma, comforting kheer, or a quick vegetable upma. A versatile pantry staple.'

  ELSE description  -- preserve any existing descriptions for unmatched products
END;
